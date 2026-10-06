"""Ordered fallback across video providers.

The failure this exists for: Luma's account runs out of credits mid-session.
Before the chain, that was a 502 on every video request until somebody
noticed. Now it is a log line and the next provider's turn.

The policy, in one place so it can be argued with:

* **Try providers in configured order**, skipping any that is not configured
  (no key). An unconfigured provider is not a failure; it is just absent.
* **``ProviderUnavailable`` advances.** Credits, auth, rate limit, transport —
  all things another vendor can answer for.
* **``ProviderRejected`` stops.** The provider refused *this input*. Replaying
  a moderated prompt against the next bill buys nothing and costs a call.
* **When every live provider is out, the mock may stand in** if
  ``VIDEO_ALLOW_MOCK_FALLBACK`` allows it. That is a deliberate choice to keep
  answering instead of erroring; the job is stamped ``provider='mock'`` and
  ``engine='luma-mock'`` so it can never be mistaken for a real render.
* **With nothing at all, raise.** The views already handle
  :class:`~.base.VideoProviderError` by marking the job FAILED with a reason,
  which is far better than a job stuck pending forever.

Polling and cancelling are routed by ``provider`` rather than re-tried, for
one simple reason: a job id is only meaningful to the vendor that issued it.
"""

import logging
from typing import Optional, Sequence

from .base import (
    ProviderRejected,
    ProviderUnavailable,
    VideoProvider,
    VideoProviderError,
)

logger = logging.getLogger(__name__)


class VideoProviderChain(VideoProvider):
    """A ``VideoProvider`` that delegates to the first vendor able to answer."""

    key = 'chain'
    live = True

    def __init__(
        self,
        providers: Sequence[VideoProvider] = (),
        mock: Optional[VideoProvider] = None,
    ):
        self.providers = [p for p in providers if p.configured]
        self.mock = mock

    # -- presentation -----------------------------------------------------
    @property
    def configured(self) -> bool:
        """A chain can serve if it has a live provider or a mock to fall back on."""
        return bool(self.providers) or self.mock is not None

    @property
    def engine(self) -> str:
        """Best-known engine, used only when a submit result lacks its own.

        The submit result always carries the engine of the provider that
        actually served, so this is a fallback for callers that never
        submitted (and for test doubles). First configured live provider wins;
        the mock only speaks when nothing live is available.
        """
        if self.providers:
            return self.providers[0].engine
        if self.mock is not None:
            return self.mock.engine
        return ''

    @property
    def live_providers(self) -> list[VideoProvider]:
        return list(self.providers)

    # -- submit -----------------------------------------------------------
    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        failures: list[str] = []

        for provider in self.providers:
            try:
                result = provider.submit_video_generation(
                    prompt=prompt,
                    image_url=image_url,
                    duration=duration,
                    aspect_ratio=aspect_ratio,
                )
            except ProviderRejected as exc:
                # Stop here: the next vendor would refuse the same input.
                logger.warning(
                    'Video provider %s rejected the prompt: %s', provider.key, exc
                )
                raise
            except VideoProviderError as exc:
                failures.append(f'{provider.key}: {exc}')
                logger.warning(
                    'Video provider %s unavailable, trying the next: %s',
                    provider.key,
                    exc,
                )
                continue

            _stamp(result, provider)
            if failures:
                logger.info(
                    'Served by %s after falling through from: %s',
                    provider.key,
                    '; '.join(failures),
                )
            return result

        reason = '; '.join(failures) if failures else 'no live provider configured'

        if self.mock is not None:
            # Deliberate: answering beats erroring here. The job still records
            # which provider served it, so nothing fake is credited to a vendor.
            logger.error(
                'Every live video provider is unavailable (%s); falling back '
                'to the mock. Renders will report completed with an '
                'unplayable placeholder URL. Set VIDEO_ALLOW_MOCK_FALLBACK=0 '
                'to fail loudly instead.',
                reason,
            )
            result = self.mock.submit_video_generation(
                prompt=prompt,
                image_url=image_url,
                duration=duration,
                aspect_ratio=aspect_ratio,
            )
            _stamp(result, self.mock)
            return result

        raise ProviderUnavailable(
            f'Video generation is not available: {reason}'
        )

    # -- poll / cancel ----------------------------------------------------
    def get_job_status(self, job_id: str, provider: str = '') -> dict:
        target = self.resolve(provider)
        if target is None:
            return {
                'error': f'No video provider {provider!r} is configured',
                'status': 'unknown',
            }
        return target.get_job_status(job_id)

    def cancel_job(self, job_id: str, provider: str = '') -> dict:
        target = self.resolve(provider)
        if target is None:
            # Nothing remote to cancel, but the caller still means it locally.
            return {'id': job_id, 'status': 'cancelled', 'message': 'Job cancelled'}
        return target.cancel_job(job_id)

    # -- routing ----------------------------------------------------------
    def resolve(self, provider_key: str) -> Optional[VideoProvider]:
        """Find the provider that owns a stored job id.

        An unknown or absent key falls back to the first configured live
        provider — the right answer for rows written before ``provider``
        existed, which were all issued by whichever vendor was primary. The
        migration backfills those, so this only matters for rows created
        outside the submit path (tests, the admin).
        """
        if provider_key == 'mock':
            return self.mock
        if provider_key:
            for provider in self.providers:
                if provider.key == provider_key:
                    return provider
            # The job's vendor is no longer configured (key rotated, model
            # removed). Reporting that is better than silently polling a
            # different vendor with someone else's job id.
            logger.warning(
                'Video job provider %r is not configured; not polling it',
                provider_key,
            )
            return None
        if self.providers:
            return self.providers[0]
        return self.mock


def _stamp(result: dict, provider: VideoProvider) -> dict:
    """Record which vendor served this submit, on the result the view reads.

    Set rather than overwritten: a provider that reports its own identity
    (all three do) keeps it, so a future provider cannot be mislabelled.
    """
    if isinstance(result, dict):
        result.setdefault('provider', provider.key)
        result.setdefault('engine', provider.engine)
    return result
