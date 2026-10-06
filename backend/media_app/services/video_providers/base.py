"""Provider-agnostic contracts for video generation.

The codebase used to speak Luma directly: one client, one exception type, one
meaning of ``engine``. That held while there was exactly one vendor. It stops
holding the moment a second vendor exists, because the interesting failure is
no longer "did Luma answer" but "is *somebody* able to render this".

So the shapes below are deliberately vendor-neutral:

* :class:`VideoProviderError` is the single exception family every view
  catches. :data:`LumaAIError` is an alias of it, so the existing
  ``except LumaAIError`` call sites keep working while new code names the
  thing it actually means.
* :class:`ProviderUnavailable` and :class:`ProviderRejected` split the one
  decision a fallback chain has to make: *advance* to the next provider, or
  *stop* because this input will fail everywhere too. Running out of credits
  is the first kind; a prompt the moderator refuses is the second.
* :class:`VideoProvider` is the interface every provider implements. The chain
  in :mod:`.chain` only ever sees this, never a concrete vendor.
"""

from abc import ABC, abstractmethod
from typing import Any, Optional

__all__ = [
    'LUMA_API_BASE',
    'LumaAIError',
    'LumaAIService',
    'ProviderRejected',
    'ProviderUnavailable',
    'VideoProvider',
    'VideoProviderError',
    'normalise_progress',
    'result_field',
]


#: The retired Dream Machine endpoint. Kept only so existing imports and
#: assertions about the scheme keep resolving; live traffic goes to the
#: Luma Agents API, which lives on a different host.
LUMA_API_BASE = 'https://api.lumalabs.ai/dream-machine/v1'


class VideoProviderError(Exception):
    """Raised when a video provider fails to start, poll or cancel a job."""


#: Backwards-compatible name. Views and tests were written when Luma was the
#: only provider; aliasing rather than subclassing means ``except LumaAIError``
#: still catches fal.ai and chain failures, not just Luma's.
LumaAIError = VideoProviderError


class ProviderUnavailable(VideoProviderError):
    """This provider cannot serve the request right now.

    Configuration missing, credits exhausted, endpoint unreachable, auth
    failed. The chain treats it as "try the next provider" — which is the
    whole point of the fallback, since running out of Luma credits is exactly
    what this class exists to absorb.
    """


class ProviderRejected(VideoProviderError):
    """This provider refused the input itself.

    Content moderation, a malformed prompt, an unsupported aspect ratio.
    Falling through to the next provider would just replay the same refusal
    against a different bill, so the chain stops here and reports the reason.
    """


class VideoProvider(ABC):
    """Interface implemented by Luma, fal.ai and the local mock.

    Implementations must be cheap to construct — the chain builds them per
    process, not per request — and must never raise anything outside
    :class:`VideoProviderError` for an expected failure. An unexpected
    exception is allowed to propagate: that is a bug, and it should surface
    as one rather than be swallowed into an infinite retry.
    """

    #: Stable machine key, stored on ``VideoGenerationJob.provider`` so a poll
    #: knows which vendor's job id it is holding. Must be unique in the chain.
    key: str = ''

    #: Human-facing model credit, stored on the job. Unique per provider so
    #: "AI-generated video (x)" never credits the wrong vendor.
    engine: str = ''

    #: False for the mock: lets callers tell a real render from a placeholder
    #: without importing the concrete class.
    live: bool = True

    @abstractmethod
    def submit_video_generation(
        self,
        prompt: str,
        image_url: Optional[str] = None,
        duration: int = 5,
        aspect_ratio: str = '16:9',
    ) -> dict:
        """Start a render. Returns at least ``id`` and ``status``."""

    @abstractmethod
    def get_job_status(self, job_id: str) -> dict:
        """Return the normalised job dict the views already consume."""

    @abstractmethod
    def cancel_job(self, job_id: str) -> dict:
        """Best-effort cancel. Never raises for an unsupported operation."""

    @property
    def configured(self) -> bool:
        """True when this provider has what it needs to attempt a render."""
        return True


#: Historical name for the interface.
LumaAIService = VideoProvider


def normalise_progress(value: Any, state: str) -> int:
    """Coerce a provider progress value to an integer 0-100.

    Luma has reported ``progress`` as both a 0..1 fraction and a 0..100
    percentage across API versions, so scale by magnitude instead of assuming
    one. Anything missing, non-numeric or out of range falls back to a value
    derived from the state, because a stuck 0% is worse than an estimate: the
    client renders it as a progress bar and the user watches a dead meter.

    The state table covers every vendor's vocabulary — Luma's retired
    ``in_progress``, the Agents API's ``processing``, and the mock's
    ``pending`` — so a state this function has never seen still yields a
    moving bar rather than 0.
    """
    if state == 'completed':
        return 100
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return {
            'queued': 0,
            'pending': 0,
            'in_progress': 50,
            'processing': 50,
        }.get(state, 0)
    # Note the explicit `and`: `0 < value <= 1` would chain as
    # `(0 < value) and (0 <= 1)`, which is true for every input.
    if 0 < value <= 1:
        value = value * 100
    return max(0, min(100, round(value)))


#: The name the views and its tests import.
_normalise_progress = normalise_progress


def result_field(result: Any, name: str, default: str = '') -> str:
    """Read a plain string out of a submit result, or ``default``.

    Tests stub the provider with ``mock.Mock()``; calling ``.get()`` on one
    hands back a Mock, which would then be written into a ``CharField`` and
    fail at save time with an error that points nowhere near the cause. Only a
    real ``dict`` carrying a real ``str`` is trusted, so a test double that
    returns nothing degrades to the default instead of corrupting the row.
    """
    if isinstance(result, dict):
        value = result.get(name)
        if isinstance(value, str):
            return value
    return default
