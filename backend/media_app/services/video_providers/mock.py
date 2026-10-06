"""Local mock provider — keeps the job lifecycle testable without a vendor.

It is deliberately *not* a fallback anyone should see in production: it marks
jobs ``completed`` and points ``video_url`` at a
``storage.example.com`` placeholder that plays nothing. It exists so local
development and the test suite can exercise pending → processing → completed
without spending a generation, and — per the configured fallback policy — so a
deployment whose providers have both run dry can still answer a request rather
than 502.

Whatever it does produce is stamped ``provider='mock'`` and
``engine='luma-mock'`` so nothing it does is ever credited to a real vendor,
and so :func:`media_app.services.video_storage.store_video_asset` skips the
download instead of chasing a URL that will never resolve.
"""

import logging
import random
import time
import uuid
from typing import Optional

from .base import VideoProvider

logger = logging.getLogger(__name__)


def _timezone_now():
    """Lazy import to avoid circular imports at module level."""
    from django.utils import timezone

    return timezone.now()


class MockVideoProvider(VideoProvider):
    """Simulates video generation for local development.

    Job state lives on ``VideoGenerationJob``, so it survives server
    restarts. Each poll randomly advances the job from pending → processing →
    completed so the frontend can watch the full lifecycle.
    """

    key = 'mock'
    live = False
    # Named apart from every live engine so a job generated against the mock
    # is never credited to a vendor that did not make it.
    engine = 'luma-mock'

    @property
    def configured(self) -> bool:
        return True

    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        return {
            'id': f'luma_{uuid.uuid4().hex[:12]}',
            'status': 'pending',
            'created_at': time.time(),
            'engine': self.engine,
            'provider': self.key,
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
            job.progress_percent = 50
            job.save(update_fields=['status', 'progress_percent', 'updated_at'])
        elif job.status == VideoGenerationJob.Status.PROCESSING and random.random() > 0.7:
            job.status = VideoGenerationJob.Status.COMPLETED
            job.video_url = f'https://storage.example.com/videos/{job_id}.mp4'
            job.thumbnail_url = f'https://storage.example.com/thumbnails/{job_id}.jpg'
            job.duration = random.randint(5, 15)
            job.progress_percent = 100
            job.completed_at = _timezone_now()
            job.save(update_fields=[
                'status', 'video_url', 'thumbnail_url', 'duration',
                'progress_percent', 'completed_at', 'updated_at',
            ])
        elif job.status == VideoGenerationJob.Status.PROCESSING:
            # Crawl toward 95 so the client's progress bar visibly moves. Left
            # at 0 it reads as a hung request rather than a rendering video.
            elapsed = (_timezone_now() - job.created_at).total_seconds()
            creep = min(95, 50 + int(elapsed // 10) * 5)
            if creep > job.progress_percent:
                job.progress_percent = creep
                job.save(update_fields=['progress_percent', 'updated_at'])

        return {
            'id': job_id,
            'status': job.status,
            'progress': job.progress_percent,
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


#: Historical name, still referenced by tests and by the compat shim.
MockLumaAIService = MockVideoProvider
