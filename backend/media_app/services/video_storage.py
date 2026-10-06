"""Persist a completed provider render as a local file.

The provider hands back a CDN URL that belongs to the provider: it can expire,
be rate-limited, or disappear when the account does. ``store_video_asset``
pulls the finished video into ``VideoGenerationJob.video_file`` the moment the
job reports completed — the same contract ``AudioNarrationJob.audio_file``
already keeps for narration — so playback survives the provider and a finished
render is never regenerated just to fetch it again.

Failure is deliberately non-fatal: a job whose bytes could not be stored stays
COMPLETED with the remote URL, which is exactly how this worked before the
field existed. Losing the local copy degrades to the old behaviour; failing
the job would be a regression dressed up as strictness.
"""

import ipaddress
import logging
import socket
from urllib.parse import urljoin, urlparse

import requests as http_requests
from django.conf import settings
from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)

# Luma renders are short (5-30s) — even generous, a 720p clip lands well under
# this. The cap exists so a misrouted response cannot fill the disk.
MAX_VIDEO_BYTES = 256 * 1024 * 1024
_DOWNLOAD_TIMEOUT = (10, 120)  # (connect, read)
_REDIRECT_STATUSES = {301, 302, 303, 307, 308}
_MAX_REDIRECTS = 3
_CHUNK = 64 * 1024


def _is_public_host(host: str) -> bool:
    """True when every address ``host`` resolves to is publicly routable.

    The URL comes from the provider over TLS, but the same guard the crawler
    uses still applies here: one poisoned or misconfigured response must not
    aim the server at loopback, LAN, or cloud metadata.
    """
    try:
        infos = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    except socket.gaierror:
        return False
    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        mapped = getattr(addr, 'ipv4_mapped', None)
        if mapped is not None:
            addr = mapped
        if not addr.is_global:
            return False
    return True


def _validate_url(url: str) -> str | None:
    """Return the first problem with ``url``, or None when it is fetchable."""
    parsed = urlparse(url)
    if parsed.scheme != 'https':
        return f'non-https scheme {parsed.scheme!r}'
    if not parsed.hostname:
        return 'no host'
    if not _is_public_host(parsed.hostname):
        return f'host {parsed.hostname!r} does not resolve to public space'
    return None


def _guess_extension(url: str, content_type: str) -> str:
    path = urlparse(url).path.lower()
    for ext in ('.mp4', '.webm', '.mov'):
        if path.endswith(ext):
            return ext
    if 'webm' in content_type:
        return '.webm'
    return '.mp4'


def _is_mock_render(job) -> bool:
    """True when the job was served by the mock rather than a vendor.

    Read from both the provider key and the engine credit: rows written
    before ``provider`` existed only carry the engine, and the mock's engine
    has always ended in ``-mock`` precisely so it stays identifiable.
    """
    provider = getattr(job, 'provider', '') or ''
    if provider == 'mock':
        return True
    return (getattr(job, 'engine', '') or '').endswith('-mock')


def _any_live_key() -> bool:
    """True when at least one vendor could have produced a real render."""
    return bool(
        getattr(settings, 'LUMA_API_KEY', '')
        or getattr(settings, 'FAL_API_KEY', '')
    )


def _looks_like_video(head: bytes, content_type: str) -> bool:
    """Accept real container bytes, not whatever a host happens to serve.

    A ``video/*`` content type alone would let an HTML error page through if
    a redirect ever landed somewhere unexpected; ``ftyp`` at byte 4 is the
    ISO-BMFF (mp4) brand box every .mp4 carries.
    """
    if len(head) < 12:
        return False
    if content_type.startswith('video/'):
        return True
    return head[4:8] == b'ftyp'


def store_video_asset(job) -> bool:
    """Download ``job.video_url`` into ``job.video_file``. True when stored.

    Idempotent and side-effect free when there is nothing to do: already
    stored, no URL, or a job no live provider produced (mock jobs report
    placeholder URLs that never resolve to a video — attempting them would be
    a network call per poll for nothing).
    """
    if job.video_file:
        return True
    url = job.video_url or ''
    if not url:
        return False
    if _is_mock_render(job):
        # The mock never produced bytes worth keeping. Checked before the URL
        # validation below so it does not log a warning per poll about a
        # placeholder host we deliberately handed out.
        return False
    if not _any_live_key():
        # No live provider was configured, so no real render exists to keep.
        return False

    problem = _validate_url(url)
    if problem:
        logger.warning('Not storing video for job %s: %s (%s)', job.pk, problem, url)
        return False

    # Manual redirect handling: the provider's CDN may hop hosts, and each
    # hop has to pass the same validation as the first URL.
    current = url
    resp = None
    try:
        for _ in range(_MAX_REDIRECTS + 1):
            if _validate_url(current):
                logger.warning(
                    'Not storing video for job %s: redirect target failed '
                    'validation (%s)',
                    job.pk,
                    current,
                )
                return False
            resp = http_requests.get(
                current, timeout=_DOWNLOAD_TIMEOUT, stream=True, allow_redirects=False
            )
            if resp.status_code in _REDIRECT_STATUSES and resp.headers.get('location'):
                location = resp.headers['location']
                resp.close()
                resp = None
                current = urljoin(current, location)
                continue
            break
        if resp is None:
            logger.warning('Not storing video for job %s: no final response', job.pk)
            return False
        if resp.status_code >= 400:
            logger.warning(
                'Not storing video for job %s: upstream %s', job.pk, resp.status_code
            )
            return False

        content_type = (resp.headers.get('content-type') or '').split(';')[0].strip()
        chunks = []
        total = 0
        head = b''
        for chunk in resp.iter_content(_CHUNK):
            if not chunk:
                continue
            if not head:
                head = chunk[:16]
            total += len(chunk)
            if total > MAX_VIDEO_BYTES:
                logger.warning(
                    'Not storing video for job %s: exceeds %s bytes',
                    job.pk,
                    MAX_VIDEO_BYTES,
                )
                return False
            chunks.append(chunk)

        if not head or not _looks_like_video(head, content_type):
            logger.warning(
                'Not storing video for job %s: response is not a video (%s)',
                job.pk,
                content_type or 'no content-type',
            )
            return False

        data = b''.join(chunks)
        name = f'{job.pk}{_guess_extension(url, content_type)}'
        job.video_file.save(name, ContentFile(data), save=False)
        logger.info('Stored video for job %s (%s bytes)', job.pk, total)
        return True
    except http_requests.RequestException as exc:
        # Storage is best effort: the job stays completed on the remote URL.
        logger.warning('Not storing video for job %s: %s', job.pk, exc)
        return False
    finally:
        if resp is not None:
            resp.close()
