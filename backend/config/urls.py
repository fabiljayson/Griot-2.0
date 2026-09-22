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

# Serve media files directly. Django's static() helper no-ops when DEBUG is
# False, and Render runs gunicorn with no separate media server (the free tier
# has no persistent disk), so the route is registered explicitly — media is
# baked into the container from this repo's media/ directory.
urlpatterns += [
    path(
        f'{settings.MEDIA_URL.strip("/")}/<path:path>',
        serve,
        {'document_root': settings.MEDIA_ROOT},
        name='media',
    ),
]
