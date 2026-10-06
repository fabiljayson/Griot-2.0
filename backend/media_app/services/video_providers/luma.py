"""Luma provider — the Luma Agents API (Ray 3.2).

The Dream Machine client this replaced pointed at
``https://api.lumalabs.ai/dream-machine/v1``. That endpoint now returns
``403 Not authenticated`` for *every* bearer token, valid or not: the product
moved to a separate host, a separate version prefix, and a mostly different
payload. The differences that matter here:

* ``POST /generations`` takes ``model`` and ``type`` and nests output settings
  under ``video``. ``duration`` is a *string* — ``"5s"`` or ``"10s"``, nothing
  else — so the integer seconds the rest of the app speaks are snapped to the
  nearest value the API accepts.
* ``prompt`` is required. Image input exists, but as ``video.start_frame``,
  not the retired top-level ``image_url``.
* The state machine is ``queued``/``processing`` rather than
  ``pending``/``in_progress``; only the terminal pair is unchanged, which is
  all the views branch on.
* There is **no** cancel route: ``DELETE /generations/{id}`` answers 405.
  :meth:`LumaProvider.cancel_job` degrades to a no-op instead of pretending.
* Successful output is a *presigned* URL good for one hour, which is why
  :func:`media_app.services.video_storage.store_video_asset` runs the moment a
  job completes.
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

#: Agents API host. Deliberately *not* the retired Dream Machine base URL;
#: the two are not interchangeable and silently falling back to the old host
#: is what produced opaque 403s during the migration.
LUMA_AGENTS_API_BASE = 'https://agents.lumalabs.ai/v1'

#: The only model that accepts ``type: "video"``. A wrong value is a hard 400
#: (``Unknown model: ...``), so it is configurable but pinned by default.
DEFAULT_LUMA_MODEL = 'ray-3.2'

#: Ray 3.2 accepts exactly two durations. Anything the caller asked for outside
#: that pair is snapped, never rejected — a 12s request becoming 10s is a
#: better outcome than a 502 for a value the serializer happily accepted.
_LUMA_DURATIONS = ('5s', '10s')

#: HTTP statuses that mean "this vendor cannot serve us right now" rather than
#: "this request is wrong". Each one advances the fallback chain.
_UNAVAILABLE_STATUSES = {401, 402, 403, 408, 425, 429, 500, 502, 503, 504}


def luma_duration(seconds: int) -> str:
    """Snap an integer second count to a duration Ray 3.2 accepts."""
    if not isinstance(seconds, int) or seconds < 8:
        return '5s'
    return '10s'


class LumaProvider(VideoProvider):
    """Live client for the Luma Agents API."""

    key = 'luma'
    live = True

    def __init__(self, api_key: str, model: str = DEFAULT_LUMA_MODEL):
        self.api_key = api_key
        self.model = model
        self.engine = f'luma-{model}'
        self._session = http_requests.Session()
        self._session.headers.update({
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json',
        })
        # A hung socket must not pin a worker forever. Conservative for the
        # short submit, generous for the polling GETs.
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
        payload: dict = {
            'model': self.model,
            'type': 'video',
            'prompt': prompt,
            'aspect_ratio': aspect_ratio,
            'video': {
                'resolution': getattr(settings, 'LUMA_VIDEO_RESOLUTION', '720p'),
                'duration': luma_duration(duration),
            },
        }
        if image_url:
            # The retired API took a flat `image_url`; Agents takes an anchor
            # frame object. Dropping the input instead of sending the old key
            # would silently turn an image-to-video job into text-to-video.
            payload['video']['start_frame'] = {'url': image_url}

        try:
            resp = self._session.post(
                f'{LUMA_AGENTS_API_BASE}/generations', json=payload
            )
        except http_requests.RequestException as exc:
            # A timeout, DNS failure or reset is an upstream failure, not a bug
            # in this project. Left unhandled it surfaces as a 500 from the
            # view; translated here the chain can move to the next provider.
            logger.warning('Luma submit transport error: %s', exc)
            raise ProviderUnavailable(f'Could not reach Luma AI: {exc}') from exc

        if resp.status_code >= 400:
            detail = _error_detail(resp)
            if resp.status_code in _UNAVAILABLE_STATUSES:
                logger.warning(
                    'Luma submit unavailable (%s): %s', resp.status_code, detail
                )
                raise ProviderUnavailable(
                    f'Luma AI unavailable ({resp.status_code}): {detail}'
                )
            logger.error(
                'Luma submit rejected: %s %s', resp.status_code, resp.text
            )
            raise ProviderRejected(
                f'Luma AI rejected the request ({resp.status_code}): {detail}'
            )

        data = resp.json()
        return {
            'id': data.get('id', ''),
            'status': _STATE_TO_STATUS.get(data.get('state', ''), 'pending'),
            'created_at': data.get('created_at', ''),
            'engine': self.engine,
            'provider': self.key,
        }

    # -- poll -------------------------------------------------------------
    def get_job_status(self, job_id: str) -> dict:
        # The polling view calls this on every status refresh. A transport
        # error here must degrade to a still-pending job rather than a 500:
        # the render is still running on Luma's side, and failing the request
        # would both break the client's poll loop and lose the progress
        # already recorded. `status` stays non-terminal so the view takes its
        # existing "keep waiting" branch.
        try:
            resp = self._session.get(f'{LUMA_AGENTS_API_BASE}/generations/{job_id}')
        except http_requests.RequestException as exc:
            logger.warning('Luma status transport error: %s', exc)
            return {
                'error': f'Could not reach Luma AI: {exc}',
                'status': 'in_progress',
            }

        if resp.status_code == 404:
            return {'error': 'Job not found', 'status': 'unknown'}
        if resp.status_code >= 400:
            logger.error(
                'Luma status failed: %s %s', resp.status_code, resp.text
            )
            return {'error': f'API error {resp.status_code}', 'status': 'unknown'}

        data = resp.json()
        state = data.get('state', 'queued')
        status = _STATE_TO_STATUS.get(state, 'in_progress')

        result = {
            'id': job_id,
            'status': status,
            'video_url': '',
            'thumbnail_url': '',
            'duration': 0,
            # Normalised to 0-100. Luma has reported this as both a 0..1
            # fraction and a 0..100 percentage across API versions, so scale
            # by magnitude rather than assuming one.
            'progress': normalise_progress(data.get('progress'), state),
            'created_at': data.get('created_at', ''),
            'completed_at': data.get('completed_at'),
        }

        if state == 'completed':
            result['video_url'] = _first_output_url(data)
            # The Agents response does not carry a duration field; keep the
            # 5s default the retired API used so the player shows something
            # plausible instead of 00:00.
            result['duration'] = data.get('duration') or 5
        elif state == 'failed':
            result['error'] = _failure_message(data)

        return result

    # -- cancel -----------------------------------------------------------
    def cancel_job(self, job_id: str) -> dict:
        """Best-effort cancel.

        The Agents API exposes only Create and Get for generations — there is
        no DELETE, which answers 405. Calling it anyway would log a scary
        error on every user-initiated cancel, so the operation is reported as
        unsupported and the view marks the job cancelled locally regardless.
        """
        logger.info(
            'Luma Agents API has no cancel endpoint; job %s left to finish '
            'server-side',
            job_id,
        )
        return {
            'id': job_id,
            'status': 'cancelled',
            'message': 'Job cancelled locally (provider has no cancel API)',
        }


#: Retired state names on the left, the status vocabulary the rest of the app
#: reads on the right. The views branch only on `completed`/`failed`, but
#: keeping `in_progress` (rather than `processing`) means an existing test or
#: client that string-matches the old value keeps working.
_STATE_TO_STATUS = {
    'queued': 'pending',
    'pending': 'pending',
    'processing': 'in_progress',
    'in_progress': 'in_progress',
    'completed': 'completed',
    'failed': 'failed',
}


def _error_detail(resp) -> str:
    """Pull a human-readable reason out of an Agents API error body.

    The API returns ``{"detail": "..."}`` for plain errors,
    ``{"detail": [...pydantic items...]}`` for validation failures, and
    ``{"detail": ..., "error": {"code": ..., "user_message": ...}}`` for
    budget/rate failures. Rendering whichever is present beats shipping raw
    JSON to the user's job history.
    """
    try:
        body = resp.json()
    except ValueError:
        return (resp.text or '').strip()[:300]

    error = body.get('error') if isinstance(body, dict) else None
    if isinstance(error, dict):
        for field in ('user_message', 'reason'):
            message = error.get(field)
            if isinstance(message, str) and message:
                return message

    detail = body.get('detail') if isinstance(body, dict) else None
    if isinstance(detail, str):
        return detail
    if isinstance(detail, list):
        messages = [
            item.get('msg', '')
            for item in detail
            if isinstance(item, dict) and item.get('msg')
        ]
        if messages:
            return '; '.join(messages)
    return (resp.text or '').strip()[:300]


def _first_output_url(data: dict) -> str:
    """Return the first output URL, whichever shape the API used."""
    output = data.get('output')
    if isinstance(output, list):
        for entry in output:
            if isinstance(entry, dict) and entry.get('url'):
                return entry['url']
    elif isinstance(output, dict) and output.get('url'):
        return output['url']
    # Older/edge responses put the asset under `assets`.
    assets = data.get('assets')
    if isinstance(assets, dict) and assets.get('video'):
        return assets['video']
    return ''


def _failure_message(data: dict) -> str:
    """Render a terminal failure the way the moderator intended it read."""
    reason = data.get('failure_reason')
    if isinstance(reason, str) and reason:
        return reason
    code = data.get('failure_code')
    if isinstance(code, str) and code:
        # `content_moderated` etc. are codes, not sentences.
        return f'Generation failed ({code})'
    return 'Generation failed'
