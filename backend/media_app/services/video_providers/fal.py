"""fal.ai provider — queue-based text-to-video.

fal is the backup vendor: when Luma runs out of credits the chain lands here
instead of failing the user's request. Everything goes through the public
queue API, which is deliberately boring:

1. ``POST https://queue.fal.run/<model>`` returns a ``request_id`` plus the
   exact URLs for status, result and cancel.
2. ``GET .../requests/<id>/status`` reports ``IN_QUEUE`` → ``IN_PROGRESS`` →
   ``COMPLETED``.
3. ``GET .../requests/<id>`` returns the model-specific payload; video models
   put the MP4 under ``video.url``.

Two details are easy to get wrong and are handled explicitly below:

* **A failed request also reports ``COMPLETED``.** The terminal status carries
  ``error`` / ``error_type`` alongside it. Reading only the status field would
  mark a failed render complete and send the player a result URL that does not
  exist.
* **The model id is part of every request URL.** Changing ``FAL_VIDEO_MODEL``
  would strand in-flight jobs if the id were re-derived at poll time, so the
  id that actually submitted is stored alongside the request id and read back.

Auth is ``Authorization: Key <FAL_KEY>`` — ``Key``, not ``Bearer``; fal rejects
the latter.
"""

import logging
from typing import Optional

import requests as http_requests
from django.conf import settings

from .base import (
    ProviderRejected,
    ProviderUnavailable,
    VideoProvider,
    normalise_progress,
)

logger = logging.getLogger(__name__)

QUEUE_BASE = 'https://queue.fal.run'

#: Kling 2.1 standard — fast, cheap enough to be a backup, and its output
#: schema is the familiar ``video: {url}``. Overridable because fal retires
#: and renames models often.
DEFAULT_FAL_MODEL = 'fal-ai/kling-video/v2.1/standard/text-to-video'

#: Statuses meaning "not our fault, try the next provider".
_UNAVAILABLE_STATUSES = {401, 402, 403, 408, 425, 429, 500, 502, 503, 504}

#: Separator between the model id and the request id in the stored job id.
#: Neither half can contain a pipe: model ids are ``[a-z0-9-/.]`` and request
#: ids are UUIDs, so a single split is unambiguous.
_ID_SEPARATOR = '|'


def _pack_job_id(model: str, request_id: str) -> str:
    return f'{model}{_ID_SEPARATOR}{request_id}'


def _unpack_job_id(job_id: str) -> tuple[str, str]:
    """Split a stored id into ``(model, request_id)``.

    Falls back to the currently configured model for ids written before the
    separator existed (or by a test), so a hand-written id still resolves
    rather than blowing up on unpack.
    """
    if _ID_SEPARATOR in job_id:
        model, request_id = job_id.split(_ID_SEPARATOR, 1)
        return model, request_id
    return _current_model(), job_id


def _current_model() -> str:
    return getattr(settings, 'FAL_VIDEO_MODEL', DEFAULT_FAL_MODEL)


class FalProvider(VideoProvider):
    """Live client for fal.ai's queue API."""

    key = 'fal'
    live = True

    def __init__(self, api_key: str, model: str = DEFAULT_FAL_MODEL):
        self.api_key = api_key
        self.model = model
        self.engine = f'fal-{model.rsplit("/", 1)[-1]}'[:40]
        self._session = http_requests.Session()
        self._session.headers.update({
            'Authorization': f'Key {api_key}',
            'Content-Type': 'application/json',
        })
        self._session.timeout = (10, 30)

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    # -- submit -----------------------------------------------------------
    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        payload: dict = {'prompt': prompt}
        # Kling takes 5 or 10 seconds. Anything outside is snapped rather
        # than rejected, matching the Luma provider's behaviour so the same
        # request succeeds on either vendor.
        payload['duration'] = 10 if isinstance(duration, int) and duration >= 8 else 5
        payload['aspect_ratio'] = aspect_ratio
        if image_url:
            # Kling's image-to-video endpoint is a different model id; with a
            # text-to-video model the input is simply not supported.
            logger.warning(
                'fal model %s is text-to-video; dropping image_url', self.model
            )

        try:
            resp = self._session.post(
                f'{QUEUE_BASE}/{self.model}', json=payload
            )
        except http_requests.RequestException as exc:
            logger.warning('fal submit transport error: %s', exc)
            raise ProviderUnavailable(f'Could not reach fal.ai: {exc}') from exc

        if resp.status_code >= 400:
            detail = _error_detail(resp)
            if resp.status_code in _UNAVAILABLE_STATUSES:
                logger.warning(
                    'fal submit unavailable (%s): %s', resp.status_code, detail
                )
                raise ProviderUnavailable(
                    f'fal.ai unavailable ({resp.status_code}): {detail}'
                )
            logger.error('fal submit rejected: %s %s', resp.status_code, resp.text)
            raise ProviderRejected(
                f'fal.ai rejected the request ({resp.status_code}): {detail}'
            )

        data = resp.json()
        request_id = data.get('request_id', '')
        return {
            'id': _pack_job_id(self.model, request_id),
            # The queue answers instantly; the work starts on a later poll.
            'status': 'pending',
            'created_at': '',
            'engine': self.engine,
            'provider': self.key,
        }

    # -- poll -------------------------------------------------------------
    def get_job_status(self, job_id: str) -> dict:
        model, request_id = _unpack_job_id(job_id)

        try:
            resp = self._session.get(
                f'{QUEUE_BASE}/{model}/requests/{request_id}/status'
            )
        except http_requests.RequestException as exc:
            logger.warning('fal status transport error: %s', exc)
            return {
                'error': f'Could not reach fal.ai: {exc}',
                'status': 'in_progress',
            }

        if resp.status_code == 404:
            return {'error': 'Job not found', 'status': 'unknown'}
        if resp.status_code >= 400:
            logger.error('fal status failed: %s %s', resp.status_code, resp.text)
            return {'error': f'API error {resp.status_code}', 'status': 'unknown'}

        data = resp.json()
        queue_state = data.get('status', 'IN_PROGRESS')

        if queue_state == 'IN_QUEUE':
            return self._progress_result(job_id, 'pending', 0)
        if queue_state == 'IN_PROGRESS':
            return self._progress_result(job_id, 'in_progress', 50)

        # COMPLETED. fal uses the same word for "here is your video" and
        # "your request died", so the error field is the real discriminator.
        error = data.get('error')
        if error:
            error_type = data.get('error_type')
            message = str(error)
            if error_type:
                message = f'{message} ({error_type})'
            logger.warning('fal request failed: %s', message)
            return {
                'id': job_id,
                'status': 'failed',
                'error': message,
                'video_url': '',
                'thumbnail_url': '',
                'duration': 0,
                'progress': 0,
                'created_at': '',
                'completed_at': None,
            }

        return self._fetch_result(model, request_id, job_id)

    def _fetch_result(self, model: str, request_id: str, job_id: str) -> dict:
        """Retrieve the finished payload once the queue reports COMPLETED."""
        try:
            resp = self._session.get(f'{QUEUE_BASE}/{model}/requests/{request_id}')
        except http_requests.RequestException as exc:
            # The render is done and paid for; losing the fetch must not fail
            # the job. Report it as still in progress so the next poll retries.
            logger.warning('fal result transport error: %s', exc)
            return {
                'error': f'Could not fetch the finished video: {exc}',
                'status': 'in_progress',
            }

        if resp.status_code >= 400:
            logger.error('fal result failed: %s %s', resp.status_code, resp.text)
            return {
                'error': f'Could not fetch the finished video '
                         f'(API error {resp.status_code})',
                'status': 'in_progress',
            }

        data = resp.json()
        video = _video_block(data)
        url = video.get('url', '') if isinstance(video, dict) else ''
        if not url:
            # COMPLETED with no playable asset is a failed render, not an
            # empty one — otherwise the job sits "done" with nothing to play.
            logger.error('fal result has no video url: %s', data)
            return {
                'id': job_id,
                'status': 'failed',
                'error': 'Provider returned no video URL',
                'video_url': '',
                'thumbnail_url': '',
                'duration': 0,
                'progress': 0,
                'created_at': '',
                'completed_at': None,
            }

        duration = video.get('duration') if isinstance(video, dict) else None
        return {
            'id': job_id,
            'status': 'completed',
            'video_url': url,
            'thumbnail_url': _thumbnail(data, video),
            'duration': int(duration) if isinstance(duration, (int, float)) else 5,
            'progress': 100,
            'created_at': '',
            'completed_at': None,
        }

    @staticmethod
    def _progress_result(job_id: str, status: str, progress: int) -> dict:
        return {
            'id': job_id,
            'status': status,
            'video_url': '',
            'thumbnail_url': '',
            'duration': 0,
            'progress': normalise_progress(progress, status),
            'created_at': '',
            'completed_at': None,
        }

    # -- cancel -----------------------------------------------------------
    def cancel_job(self, job_id: str) -> dict:
        model, request_id = _unpack_job_id(job_id)
        try:
            resp = self._session.post(
                f'{QUEUE_BASE}/{model}/requests/{request_id}/cancel'
            )
        except http_requests.RequestException as exc:
            # Cancel is best effort: a queued request that slips through is
            # billed once, which is cheaper than failing the user's action.
            logger.warning('fal cancel transport error: %s', exc)
            return {'error': f'Could not cancel: {exc}'}

        if resp.status_code >= 400 and resp.status_code != 404:
            return {'error': f'Cancel failed: {resp.status_code}'}
        return {'id': job_id, 'status': 'cancelled', 'message': 'Job cancelled'}


def _video_block(data: dict) -> dict:
    """Locate the video object across the schemas fal models use.

    ``video`` is the common shape; a few models return ``videos: [...]``.
    """
    video = data.get('video')
    if isinstance(video, dict) and video:
        return video
    videos = data.get('videos')
    if isinstance(videos, list) and videos:
        first = videos[0]
        if isinstance(first, dict):
            return first
    return {}


def _thumbnail(data: dict, video: dict) -> str:
    """Best-effort thumbnail; absent on most models, and never fatal."""
    for source in (video, data):
        if not isinstance(source, dict):
            continue
        for field in ('thumbnail_url', 'thumbnail_image_url', 'thumbnail'):
            value = source.get(field)
            if isinstance(value, str) and value.startswith('https://'):
                return value
    return ''


def _error_detail(resp) -> str:
    """Human-readable reason from a fal error body."""
    try:
        body = resp.json()
    except ValueError:
        return (resp.text or '').strip()[:300]
    if isinstance(body, dict):
        for field in ('detail', 'message', 'error'):
            value = body.get(field)
            if isinstance(value, str) and value:
                return value
            if isinstance(value, list) and value:
                return '; '.join(str(item) for item in value)
    return (resp.text or '').strip()[:300]
