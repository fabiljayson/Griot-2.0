"""Video generation providers and the fallback chain that sequences them.

Callers use :func:`get_video_service`, which returns a
:class:`~.chain.VideoProviderChain` over whichever vendors this deployment has
keys for. The historical name ``get_luma_service`` still resolves — see
:mod:`media_app.services.luma_ai` — because the call sites and the tests that
patch them are built around it, and renaming a seam is churn with no behaviour
attached.

Provider order comes from ``VIDEO_PROVIDER_ORDER`` (default ``luma,fal``). The
mock is not part of that list: it is not a vendor, it is what happens when
every vendor has said no.
"""

import logging
import os
from typing import Optional

from django.conf import settings

from .base import (
    LUMA_API_BASE,
    LumaAIError,
    LumaAIService,
    ProviderRejected,
    ProviderUnavailable,
    VideoProvider,
    VideoProviderError,
    normalise_progress,
    result_field,
)
from .chain import VideoProviderChain
from .fal import DEFAULT_FAL_MODEL, FalProvider
from .luma import DEFAULT_LUMA_MODEL, LUMA_AGENTS_API_BASE, LumaProvider
from .mock import MockLumaAIService, MockVideoProvider

logger = logging.getLogger(__name__)

__all__ = [
    'DEFAULT_FAL_MODEL',
    'DEFAULT_LUMA_MODEL',
    'FalProvider',
    'LUMA_AGENTS_API_BASE',
    'LUMA_API_BASE',
    'LumaAIError',
    'LumaAIService',
    'LumaProvider',
    'MockLumaAIService',
    'MockVideoProvider',
    'ProviderRejected',
    'ProviderUnavailable',
    'VideoProvider',
    'VideoProviderChain',
    'VideoProviderError',
    'build_video_service',
    'get_video_service',
    'normalise_progress',
    'reset_video_service',
    'result_field',
]

_SERVICE_INSTANCE: Optional[VideoProviderChain] = None


def _env_flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ('1', 'true', 'yes', 'on')


def build_video_service() -> VideoProviderChain:
    """Assemble the chain from whatever keys this deployment holds.

    Raises :class:`~.base.ProviderUnavailable` when there is neither a key nor
    a permitted mock — the same gate ``get_luma_service`` has always had, so a
    misconfigured server fails loudly instead of reporting fake renders.

    Kept separate from the memoised accessor so a test can build a fresh chain
    against ``override_settings`` without reaching for a module global.
    """
    providers: list[VideoProvider] = []

    luma_key = getattr(settings, 'LUMA_API_KEY', '') or ''
    if luma_key:
        providers.append(
            LumaProvider(
                luma_key,
                model=getattr(settings, 'LUMA_AGENTS_MODEL', DEFAULT_LUMA_MODEL),
            )
        )

    fal_key = getattr(settings, 'FAL_API_KEY', '') or ''
    if fal_key:
        providers.append(
            FalProvider(
                fal_key,
                model=getattr(settings, 'FAL_VIDEO_MODEL', DEFAULT_FAL_MODEL),
            )
        )

    order = getattr(settings, 'VIDEO_PROVIDER_ORDER', 'luma,fal')
    wanted = [part.strip().lower() for part in str(order).split(',') if part.strip()]
    by_key = {provider.key: provider for provider in providers}
    ordered = [by_key.pop(key) for key in wanted if key in by_key]
    # Anything configured but not named in the order still participates,
    # rather than a typo silently disabling a paid-for key.
    ordered.extend(by_key.values())
    for key in wanted:
        if key not in ('luma', 'fal', 'mock'):
            logger.warning('Unknown VIDEO_PROVIDER_ORDER entry %r ignored', key)

    mock: Optional[MockVideoProvider] = None
    # Two switches, two questions:
    #   VIDEO_ALLOW_MOCK_FALLBACK — may the mock stand in when every live
    #       provider is out? (Default on: answer the request rather than 502.)
    #   LUMA_ALLOW_MOCK — the pre-existing opt-in for serving the mock at all
    #       when no key is configured (local dev, test settings).
    allow_fallback = getattr(settings, 'VIDEO_ALLOW_MOCK_FALLBACK', True)
    allow_mock = bool(allow_fallback) or bool(
        getattr(settings, 'LUMA_ALLOW_MOCK', False)
    )
    if allow_mock:
        mock = MockVideoProvider()

    if not ordered and mock is None:
        # Nothing configured and no mock permitted: fail here rather than hand
        # back a chain that raises on every call with a vaguer message. The
        # name matters — operators know which variable to set.
        raise ProviderUnavailable(
            'Video generation is not configured on this server '
            '(LUMA_API_KEY and FAL_API_KEY are unset, and the mock fallback '
            'is disabled).'
        )

    if not ordered and mock is not None:
        logger.error(
            'No live video provider is configured (LUMA_API_KEY and '
            'FAL_API_KEY both unset); serving the mock. Renders will report '
            'completed with an unplayable placeholder URL.'
        )

    return VideoProviderChain(providers=ordered, mock=mock)


def get_video_service() -> VideoProviderChain:
    """Return the memoised chain for this process.

    Memoised because each provider holds a ``requests.Session`` with pooled
    connections; rebuilding per request would throw that away. Tests that
    change provider configuration must call :func:`reset_video_service` first.
    """
    global _SERVICE_INSTANCE
    if _SERVICE_INSTANCE is None:
        _SERVICE_INSTANCE = build_video_service()
        logger.info(
            'Video providers: %s (mock fallback: %s)',
            ', '.join(p.key for p in _SERVICE_INSTANCE.providers) or 'none',
            'yes' if _SERVICE_INSTANCE.mock else 'no',
        )
    return _SERVICE_INSTANCE


def reset_video_service() -> None:
    """Drop the memoised chain so the next access reads settings again."""
    global _SERVICE_INSTANCE
    _SERVICE_INSTANCE = None
