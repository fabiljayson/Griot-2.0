"""
Luma AI Dream Machine service for video generation.

Provides two modes:
  - **Live mode** (LUMA_API_KEY set): Makes real API calls to Luma AI.
  - **Mock mode** (no API key): Simulates video generation for local dev.

All job state is persisted to the ``VideoGenerationJob`` model so it survives
server restarts — no in-memory dictionaries.
"""

import logging
import random
import time
import uuid
from typing import Optional

import requests as http_requests
from django.conf import settings

logger = logging.getLogger(__name__)

LUMA_API_BASE = 'https://api.lumalabs.ai/dream-machine/v1'


class LumaAIError(Exception):
    """Raised when the Luma AI API returns an error."""


class LumaAIService:
    """Interface for submitting and polling video generation jobs.

    Subclass or replace this when a real Luma AI API key is available.
    """

    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        raise NotImplementedError

    def get_job_status(self, job_id: str) -> dict:
        raise NotImplementedError

    def cancel_job(self, job_id: str) -> dict:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Real Luma AI API client
# ---------------------------------------------------------------------------
class LiveLumaAIService(LumaAIService):
    """Production client calling the Luma AI Dream Machine REST API."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self._session = http_requests.Session()
        self._session.headers.update({
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json',
        })

    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        payload = {
            'prompt': prompt,
            'aspect_ratio': aspect_ratio,
        }
        if image_url:
            payload['image_url'] = image_url

        resp = self._session.post(f'{LUMA_API_BASE}/generations', json=payload)
        if resp.status_code >= 400:
            logger.error('Luma AI submit failed: %s %s', resp.status_code, resp.text)
            raise LumaAIError(f'Luma AI returned {resp.status_code}: {resp.text}')

        data = resp.json()
        return {
            'id': data.get('id', ''),
            'status': data.get('state', 'pending'),
            'created_at': data.get('created_at', ''),
        }

    def get_job_status(self, job_id: str) -> dict:
        resp = self._session.get(f'{LUMA_API_BASE}/generations/{job_id}')
        if resp.status_code == 404:
            return {'error': 'Job not found', 'status': 'unknown'}
        if resp.status_code >= 400:
            logger.error('Luma AI status failed: %s %s', resp.status_code, resp.text)
            return {'error': f'API error {resp.status_code}', 'status': 'unknown'}

        data = resp.json()
        state = data.get('state', 'pending')

        result = {
            'id': job_id,
            'status': state,
            'video_url': '',
            'thumbnail_url': '',
            'duration': 0,
            'created_at': data.get('created_at', ''),
            'completed_at': data.get('completed_at'),
        }

        if state == 'completed':
            assets = data.get('assets', {})
            result['video_url'] = assets.get('video', '')
            result['thumbnail_url'] = assets.get('thumbnail', '')
            # Luma doesn't always return duration; default to 5s
            result['duration'] = data.get('duration', 5)

        return result

    def cancel_job(self, job_id: str) -> dict:
        resp = self._session.delete(f'{LUMA_API_BASE}/generations/{job_id}')
        if resp.status_code >= 400:
            return {'error': f'Cancel failed: {resp.status_code}'}
        return {'id': job_id, 'status': 'cancelled', 'message': 'Job cancelled'}


# ---------------------------------------------------------------------------
# Mock client for development (state stored in DB via VideoGenerationJob)
# ---------------------------------------------------------------------------
class MockLumaAIService(LumaAIService):
    """Mock service that simulates video generation for local development.

    Job state is persisted to the ``VideoGenerationJob`` model, so it
    survives server restarts.  Each poll randomly advances the job from
    pending -> processing -> completed so the frontend can test the full
    lifecycle.
    """

    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        job_id = f'luma_{uuid.uuid4().hex[:12]}'
        return {
            'id': job_id,
            'status': 'pending',
            'created_at': time.time(),
        }

    def get_job_status(self, job_id: str) -> dict:
        from media_app.models import VideoGenerationJob

        try:
            job = VideoGenerationJob.objects.get(luma_job_id=job_id)
        except VideoGenerationJob.DoesNotExist:
            return {'error': 'Job not found', 'status': 'unknown'}

        # Simulate random progress for demo purposes
        if job.status == VideoGenerationJob.Status.PENDING and random.random() > 0.6:
            job.status = VideoGenerationJob.Status.PROCESSING
            job.save(update_fields=['status', 'updated_at'])
        elif job.status == VideoGenerationJob.Status.PROCESSING and random.random() > 0.7:
            job.status = VideoGenerationJob.Status.COMPLETED
            job.video_url = f'https://storage.example.com/videos/{job_id}.mp4'
            job.thumbnail_url = f'https://storage.example.com/thumbnails/{job_id}.jpg'
            job.duration = random.randint(5, 15)
            job.completed_at = timezone_now()
            job.save(update_fields=[
                'status', 'video_url', 'thumbnail_url', 'duration',
                'completed_at', 'updated_at',
            ])

        return {
            'id': job_id,
            'status': job.status,
            'video_url': job.video_url,
            'thumbnail_url': job.thumbnail_url,
            'duration': job.duration,
            'created_at': job.created_at.isoformat() if job.created_at else '',
            'completed_at': job.completed_at.isoformat() if job.completed_at else None,
        }

    def cancel_job(self, job_id: str) -> dict:
        from media_app.models import VideoGenerationJob

        try:
            job = VideoGenerationJob.objects.get(luma_job_id=job_id)
            job.status = VideoGenerationJob.Status.FAILED
            job.error_message = 'Cancelled by user'
            job.save(update_fields=['status', 'error_message', 'updated_at'])
        except VideoGenerationJob.DoesNotExist:
            pass
        return {'id': job_id, 'status': 'cancelled', 'message': 'Job cancelled'}


def timezone_now():
    """Lazy import to avoid circular imports at module level."""
    from django.utils import timezone
    return timezone.now()


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------
_service_instance = None


def get_luma_service() -> LumaAIService:
    """Return the appropriate Luma AI service based on configuration.

    - If ``LUMA_API_KEY`` is set in the environment, returns a real API client.
    - Otherwise, returns the mock service for development.
    """
    global _service_instance
    if _service_instance is not None:
        return _service_instance

    api_key = getattr(settings, 'LUMA_API_KEY', '') or ''
    if api_key:
        logger.info('Using live Luma AI service')
        _service_instance = LiveLumaAIService(api_key)
    else:
        logger.info('Using mock Luma AI service (no LUMA_API_KEY configured)')
        _service_instance = MockLumaAIService()

    return _service_instance
