"""A test-only URLconf mirroring the MEDIA_URL route in `config/urls.py`.

`config/urls.py` reads `settings.MEDIA_ROOT` once, when the module is imported,
and bakes it into the `document_root` of the `serve` call. Overriding
`MEDIA_ROOT` therefore does not move what the real route serves — the value is
already frozen into `urlpatterns`.

Pointing `ROOT_URLCONF` here gets a fresh import *inside* the
`override_settings` block, so this module reads the overridden value. That is
what lets the traversal tests run against a throwaway directory instead of the
repository's real `media/`.

Keep the `urlpatterns` below byte-for-byte equivalent to the media block in
`config/urls.py`; if that block changes, change this too.
"""

from django.conf import settings
from django.urls import path
from django.views.static import serve

urlpatterns = [
    path(
        f'{settings.MEDIA_URL.strip("/")}/<path:path>',
        serve,
        {'document_root': settings.MEDIA_ROOT},
        name='media',
    ),
]
