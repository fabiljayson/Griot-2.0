"""
Text-to-Speech service backed by Google Text-to-Speech (gTTS).

Generates real MP3 audio from text via the free gTTS library and returns
the audio bytes so callers can store them as a Django FileField.

No API key is required; gTTS speaks by requesting Google Translate's
public TTS endpoint. Long text is chunked internally by gTTS and the
resulting MP3 segments are concatenated into a single file.
"""
import io
import logging
import re
import uuid
from typing import Optional

from django.conf import settings

from gtts import gTTS

logger = logging.getLogger(__name__)

# Languages gTTS can speak reliably (id -> display name).
# The app's story languages (en/fr) are covered; a few regional African
# and common languages are included for future expansion.
SUPPORTED_LANGUAGES = {
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'de': 'German',
    'sw': 'Swahili',
    'ig': 'Igbo',
    'yo': 'Yoruba',
    'ha': 'Hausa',
    'am': 'Amharic',
}

# Accent variants (gTTS `tld`) exposed as extra voices for English.
ENGLISH_TLDS = {
    'en': 'com',      # US English (default)
    'en.co.uk': 'co.uk',  # UK English
}

# Maximum characters to send to the TTS engine. Keeps request time bounded;
# long-form narration above this is truncated. gTTS requests ~100-char chunks,
# so 3000 chars is ~30 sequential calls (roughly 10-30s).
DEFAULT_MAX_CHARS = 3000

# Rough characters-per-second at normal speech rate (~150 wpm).
_CHARS_PER_SECOND = 15


class TTSGenerationError(Exception):
    """Raised when speech generation fails."""


def strip_markdown(text: str) -> str:
    """Strip common Markdown syntax so gTTS does not read it aloud."""
    if not text:
        return ''
    # Code blocks / inline code
    text = re.sub(r'```[\s\S]*?```', ' ', text)
    text = re.sub(r'`([^`]*)`', r'\1', text)
    # Images: ![alt](url) -> alt
    text = re.sub(r'!\[([^\]]*)\]\([^)]*\)', r'\1', text)
    # Links: [text](url) -> text
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    # Headings
    text = re.sub(r'^#{1,6}\s*', '', text, flags=re.MULTILINE)
    # Bold / italic markers
    text = re.sub(r'(\*\*|__)(.*?)\1', r'\2', text)
    text = re.sub(r'(\*|_)([^*_]+)\1', r'\2', text)
    # Blockquotes
    text = re.sub(r'^\s*>\s?', '', text, flags=re.MULTILINE)
    # Bullet / numbered list markers
    text = re.sub(r'^\s*[-*+]\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'^\s*\d+[.)]\s+', '', text, flags=re.MULTILINE)
    # Collapse whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def resolve_language(language: str) -> str:
    """Return the gTTS language code that will actually be used."""
    lang, _ = _normalise_language(language or 'en', None)
    return lang


def build_artifact_script(artifact) -> str:
    """Build the narration text for an artifact (museum audio guide).

    Prefers the artifact's primary published story — the "story of the
    artifact" — and falls back to a script composed from the artifact's
    own metadata and description.
    """
    from stories.models import Story

    primary_story = (
        artifact.stories
        .filter(status=Story.Status.PUBLISHED)
        .order_by('id')
        .first()
    )
    if primary_story is not None:
        return strip_markdown(primary_story.content)

    parts = [
        f'This is {artifact.title}.' if artifact.title else 'This is a museum artifact.'
    ]
    if artifact.culture:
        parts.append(f'It belongs to the {artifact.culture} culture.')
    if artifact.region:
        parts.append(f'It comes from the {artifact.region} region.')
    if artifact.estimated_date:
        parts.append(f'It dates from {artifact.estimated_date}.')
    if artifact.materials:
        parts.append(f'It is made of {artifact.materials}.')
    if artifact.description:
        parts.append(artifact.description)
    return ' '.join(parts)


def _normalise_language(language: str, voice_id: Optional[str]) -> tuple:
    """
    Return a (lang, tld) tuple for gTTS.

    voice_id may encode an accent, e.g. ``en.co.uk`` -> (``en``, ``co.uk``).
    Falls back to a supported language if an unknown one is requested.
    """
    lang = (language or 'en').lower()
    tld = 'com'

    vid = (voice_id or '').lower()
    if vid in ENGLISH_TLDS:
        lang, tld = 'en', ENGLISH_TLDS[vid]
    elif '.' in vid:
        candidate, maybe_tld = vid.split('.', 1)
        if candidate in SUPPORTED_LANGUAGES:
            lang = candidate
            if candidate == 'en':
                tld = maybe_tld or 'com'
    elif vid in SUPPORTED_LANGUAGES:
        lang = vid

    if lang not in SUPPORTED_LANGUAGES:
        lang = 'en'
    return lang, tld


class GTTSNarrationService:
    """Generate speech narration with gTTS."""

    def __init__(self, max_chars: int = None):
        self.max_chars = max_chars or getattr(
            settings, 'TTS_MAX_CHARS', DEFAULT_MAX_CHARS
        )

    # ------------------------------------------------------------------
    # Voices
    # ------------------------------------------------------------------
    def list_voices(self, language: Optional[str] = None) -> list:
        """
        List available voices.

        gTTS has no distinct speaker models, so each entry is a
        language (with accent variants for English) and a neutral label.
        """
        voices = []
        for lang in SUPPORTED_LANGUAGES:
            if language and lang != language:
                continue
            voices.append({
                'id': lang,
                'name': SUPPORTED_LANGUAGES[lang],
                'gender': 'neutral',
                'language': lang,
            })
        if language and language != 'en':
            return voices
        # English accent variants (the base 'en' voice is already added above).
        for vid, tld in ENGLISH_TLDS.items():
            if vid == 'en':
                continue
            if language and vid != language and not vid.startswith(f'{language}.'):
                continue
            label = 'English (UK)' if tld == 'co.uk' else 'English (US)'
            voices.append({
                'id': vid,
                'name': label,
                'gender': 'neutral',
                'language': 'en',
            })
        return voices

    # ------------------------------------------------------------------
    # Narration
    # ------------------------------------------------------------------
    def submit_narration(
        self,
        text: str,
        language: str = 'en',
        voice_id: Optional[str] = None,
        speed: float = 1.0,
        slug: str = 'narration',
    ) -> dict:
        """
        Synthesize speech for ``text`` and return the MP3 bytes.

        Returns:
            dict with keys: ``status``, ``audio_bytes``, ``filename``,
            ``duration``, ``file_size``, ``language``, ``voice_id``.

        Raises:
            TTSGenerationError: if the request to Google TTS fails.
        """
        plain_text = strip_markdown(text).strip()
        if not plain_text:
            raise TTSGenerationError('No narratable text provided.')

        # Keep request time bounded.
        if len(plain_text) > self.max_chars:
            logger.warning('Truncating narration text from %d to %d chars', len(plain_text), self.max_chars)
            plain_text = plain_text[: self.max_chars].rsplit(' ', 1)[0]

        lang, tld = _normalise_language(language, voice_id)
        # gTTS only supports "normal" vs "slow"; treat < 1.0x as slow.
        slow = speed < 1.0

        try:
            tts = gTTS(text=plain_text, lang=lang, slow=slow, tld=tld)
            buffer = io.BytesIO()
            tts.write_to_fp(buffer)
            audio_bytes = buffer.getvalue()
        except Exception as exc:  # gtts raises gTTSError / request errors
            logger.exception('gTTS synthesis failed for lang=%s', lang)
            raise TTSGenerationError(f'Speech generation failed: {exc}') from exc

        if not audio_bytes:
            raise TTSGenerationError('Speech generation returned an empty file.')

        # Rough duration estimate (~15 chars/sec normal, ~10/sec slow).
        rate = _CHARS_PER_SECOND if not slow else 10
        duration = max(1, int(len(plain_text) / rate))
        filename = f'{slug or "narration"}-{uuid.uuid4().hex[:8]}.mp3'

        return {
            'status': 'completed',
            'audio_bytes': audio_bytes,
            'filename': filename,
            'duration': duration,
            'file_size': len(audio_bytes),
            'language': lang,
            'voice_id': f'{lang}.{tld}' if tld != 'com' else lang,
        }


# Singleton instance
tts_service = GTTSNarrationService()


def get_tts_service() -> GTTSNarrationService:
    """Get the TTS service instance."""
    return tts_service
