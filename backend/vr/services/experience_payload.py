"""Build the JSON Unity loads an experience from.

One module builds every payload Unity and Flutter see. The alternative — a
serializer here and an ad-hoc `dict` in the launch view — is how the phone and
the headset end up disagreeing about the shape of the same object, and the
mismatch only shows up on a headset, which is the slowest place to debug it.

Two rules hold for everything built here:

* **No credentials.** The payload carries content and asset references only. No
  storage key, no provider key, no API token, no user email. A headset app is
  the least trustworthy client in the system and the least auditable.
* **Absolute `https` asset URLs** built from `SITE_URL`, not from
  `request.build_absolute_uri`. The deployed service sits behind Render's proxy,
  so a request-derived host depends on proxy headers being right; `SITE_URL` is
  configuration that is either correct or obviously wrong.
"""

from django.conf import settings

from media_app.models import AudioNarrationJob
from stories.models import Story

from .experiences import published_placements


def absolute_media_url(reference) -> str | None:
    """Resolve a media reference to an absolute URL, or None.

    Accepts the three shapes the models actually produce: an absolute URL
    (`audio_url`), a storage-relative path (`audio_file.url`, `/media/...`), and
    a bare media path (`audio/narrations/x.mp3`).
    """
    if not reference:
        return None

    value = str(reference).strip()
    if not value:
        return None
    if value.startswith(('http://', 'https://')):
        return value

    base = str(getattr(settings, 'SITE_URL', '') or '').rstrip('/')
    if value.startswith('/'):
        return f'{base}{value}'

    media = str(getattr(settings, 'MEDIA_URL', '/media/'))
    if not media.endswith('/'):
        media = f'{media}/'
    return f'{base}{media}{value}'


def narration_payload(job: AudioNarrationJob | None) -> dict | None:
    """Describe a narration job for playback inside VR.

    Only a finished, playable job is returned: a `pending` job would send Unity
    to a URL with nothing behind it. `is_synthetic` and `attribution` are passed
    through so the headset can label a machine voice as a machine voice rather
    than letting a listener assume they are hearing a community elder.
    """
    if job is None or job.status != AudioNarrationJob.Status.COMPLETED:
        return None

    url = absolute_media_url(job.audio_file) or absolute_media_url(job.audio_url)
    if not url:
        return None

    return {
        'id': job.pk,
        'audio_url': url,
        'language': job.language,
        'voice_id': job.voice_id,
        'duration': job.duration,
        'is_synthetic': bool(getattr(job, 'is_synthetic', True)),
        'attribution': str(getattr(job, 'attribution', '') or ''),
    }


def story_reference(story) -> dict:
    """Minimal story reference — enough to request the full story over HTTP."""
    return {
        'id': story.pk,
        'slug': story.slug,
        'title': story.title,
        'language': story.language,
    }


def published_story_references(artifact) -> list[dict]:
    """Only stories a reader is allowed to read.

    A draft or pending story attached to an artifact must not become visible
    because the artifact is in a VR scene — the review workflow that
    `status='published'` represents applies to the headset too.
    """
    return [
        story_reference(story)
        for story in artifact.stories.filter(status=Story.Status.PUBLISHED)
    ]


def artifact_payload(artifact, *, placement=None) -> dict:
    """The artifact plus whatever placement metadata applies to it."""
    payload = {
        'id': artifact.pk,
        'slug': artifact.slug,
        'name': artifact.title,
        'description': artifact.description,
        'category': artifact.category,
        'content_type': artifact.content_type,
        'culture': artifact.culture,
        'region': artifact.region,
        'estimated_date': artifact.estimated_date,
        'materials': artifact.materials,
        'dimensions': artifact.dimensions,
        'image': absolute_media_url(artifact.image),
        'museum_name': artifact.museum_name,
        'floor': artifact.floor,
        'display_case': artifact.display_case,
        'stories': published_story_references(artifact),
    }

    if placement is not None:
        payload.update({
            'order': placement.order,
            'model_url': absolute_media_url(placement.model_url),
            'model_scale': placement.model_scale,
            'is_interactive': placement.is_interactive,
            'narration': narration_payload(placement.narration),
        })

    return payload


def experience_summary(experience) -> dict:
    """The experience without its placements — used for lists and for the
    Flutter launch response, which does not need the scene contents."""
    return {
        'id': experience.pk,
        'slug': experience.slug,
        'title': experience.title,
        'description': experience.description,
        'scene_identifier': experience.scene_identifier,
        'thumbnail': absolute_media_url(experience.thumbnail),
        'language': experience.language,
    }


def experience_payload(experience) -> dict:
    """The full experience Unity loads and then materialises into a scene."""
    placements = list(published_placements(experience))

    return {
        **experience_summary(experience),
        'environment': experience.environment,
        'museum_name': experience.museum_name,
        'region': experience.region,
        'culture': experience.culture,
        'updated_at': experience.updated_at.isoformat(),
        'artifact_count': len(placements),
        'artifacts': [
            artifact_payload(placement.artifact, placement=placement)
            for placement in placements
        ],
    }
