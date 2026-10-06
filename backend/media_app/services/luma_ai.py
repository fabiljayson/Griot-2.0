"""Backwards-compatible facade over the video provider chain.

This module used to *be* the Luma client. It now exists so that the existing
call sites — ``from .services.luma_ai import get_luma_service`` and their
``mock.patch('...views.get_luma_service')`` seams — keep working unchanged
while the implementation moved into :mod:`.video_providers`.

What moved where:

===========================  ==========================================
This module                  :mod:`.video_providers`
===========================  ==========================================
``get_luma_service()``       :func:`.video_providers.get_video_service`
``LiveLumaAIService``        :class:`.video_providers.luma.LumaProvider`
``MockLumaAIService``        :class:`.video_providers.mock.MockVideoProvider`
``LumaAIError``              :class:`.video_providers.base.VideoProviderError`
``_normalise_progress``      :func:`.video_providers.base.normalise_progress`
``LUMA_API_BASE``            retired Dream Machine host (historical)
===========================  ==========================================

``get_luma_service`` returns the *chain*, not a Luma client — that is the
point of the migration. The name is kept because a dozen tests patch it by
path; renaming a seam is churn with no behaviour attached.
"""

from .video_providers import (
    LUMA_API_BASE,
    LumaAIError,
    LumaAIService,
    get_video_service,
    normalise_progress,
)
from .video_providers.luma import LumaProvider
from .video_providers.mock import MockVideoProvider

#: Everything this facade still answers to. Declared so the re-exports read as
#: intentional rather than as imports nobody got around to deleting.
__all__ = [
    'LUMA_API_BASE',
    'LumaAIError',
    'LumaAIService',
    'LiveLumaAIService',
    'MockLumaAIService',
    '_normalise_progress',
    'get_luma_service',
    'get_video_service',
]

#: The live client. The class is the same object under both names, so an
#: ``isinstance(service, LiveLumaAIService)`` written against the old module
#: still answers correctly for a chain holding one.
LiveLumaAIService = LumaProvider
MockLumaAIService = MockVideoProvider

#: The name views and tests import.
get_luma_service = get_video_service

#: The name the views import to compute a progress bar.
_normalise_progress = normalise_progress


def __getattr__(name):
    """Explain the move instead of raising an opaque ImportError.

    Somebody's local script or forgotten test may still ask for something this
    module no longer owns; pointing at the new home costs one line and saves
    the hunt.
    """
    if name == '_service_instance':
        raise AttributeError(
            'the memoised service moved: call '
            'video_providers.reset_video_service() instead of clearing '
            'luma_ai._service_instance'
        )
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')
