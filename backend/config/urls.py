"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView
from django.views.static import serve

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('api.urls')),
    # Server-rendered web interface (mirrors the Flutter mobile app).
    path('', include('web.urls')),
    # Legacy artifact QR landing route (pre-consolidation printed codes):
    # permanently redirect to the canonical web detail page. The deprecated
    # `artifacts` app itself is retired (see artifacts/README.md); only its
    # migration history remains on disk.
    path(
        'artifacts/<slug:slug>/',
        RedirectView.as_view(url='/artifact/%(slug)s/', permanent=True),
        name='legacy-artifact-redirect',
    ),
]

# Serve media files directly.
#
# Why not the usual alternatives:
#   * `django.conf.urls.static.static()` is a no-op unless DEBUG is True, so it
#     is not an option in production.
#   * WhiteNoise is for STATIC_ROOT, not user media, and adding a second
#     whitenoise-style handler would mean serving uploads as if they were
#     versioned build artefacts.
#   * Render's free tier has no persistent disk and no separate media service,
#     so there is nothing to hand this off to. The files are baked into the
#     image from this repo's media/ directory.
#
# What this costs, stated plainly: `django.views.static.serve` is documented as
# "not hardened for production use". It is safe against path traversal
# (`safe_join` normalises and rejects anything escaping MEDIA_ROOT — pinned by
# MediaServingTests), but it reads each file per request with no caching, no
# Range support and no ETag, which matters for the audio and video this app
# serves. That is an accepted trade-off for a single-instance free-tier
# deployment, not an oversight.
#
# The moment there is a real disk or a CDN in front, delete this block and
# point MEDIA_URL there. `MediaServingTests` will then fail, which is the
# intended signal that the route moved.
urlpatterns += [
    path(
        f'{settings.MEDIA_URL.strip("/")}/<path:path>',
        serve,
        {'document_root': settings.MEDIA_ROOT},
        name='media',
    ),
]
