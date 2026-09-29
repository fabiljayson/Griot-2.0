"""
Per-user daily caps for billable/expensive media generation.

Luma bills per generation and gTTS calls Google Translate's public endpoint, so
both paths need a hard ceiling on how much one account can start per day. This
module holds that ceiling logic in exactly one place so the REST API
(``media_app/views.py``) and the server-rendered web actions
(``web/services.py``) cannot drift — the web path previously re-implemented
generation and silently skipped the cap, which let a contributor with a handful
of stories start unbounded paid renders.

The window is a rolling 24 hours, not a calendar day, so the allowance cannot
be reset early by straddling midnight and needs no timezone bookkeeping.

Cache hits are checked by the caller *before* consulting this module, so
re-reading a story that already has a narration never costs quota.
"""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone


def within_daily_cap(queryset, cap) -> bool:
    """True when fewer than ``cap`` rows in ``queryset`` were created in the
    last 24 hours.

    ``queryset`` must already be filtered to a single user. A falsy ``cap``
    (0 or None) disables the limit entirely, matching the API's existing
    "no cap configured" behaviour.
    """
    if not cap:
        return True
    window_start = timezone.now() - timedelta(days=1)
    return queryset.filter(created_at__gte=window_start).count() < cap


def video_cap() -> int:
    return int(getattr(settings, 'VIDEO_GENERATIONS_PER_USER_PER_DAY', 5))


def audio_cap() -> int:
    return int(getattr(settings, 'AUDIO_NARRATIONS_PER_USER_PER_DAY', 10))


def video_within_cap(user) -> bool:
    """True when ``user`` may start another AI video right now."""
    from media_app.models import VideoGenerationJob

    return within_daily_cap(
        VideoGenerationJob.objects.filter(user=user), video_cap(),
    )


def audio_within_cap(user) -> bool:
    """True when ``user`` may synthesize another narration right now."""
    from media_app.models import AudioNarrationJob

    return within_daily_cap(
        AudioNarrationJob.objects.filter(user=user), audio_cap(),
    )
