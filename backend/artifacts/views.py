"""
Views for the Artifacts app.

Provides the mobile-optimized artifact detail page that users see
when they scan a QR code.
"""

from django.http import Http404
from django.shortcuts import get_object_or_404, render

from .models import Artifact


def artifact_detail(request, slug):
    """
    Display artifact details with story, audio, and video.
    
    This is the landing page for QR code scans - optimized for
    mobile viewing with a clean, app-like interface.
    """
    artifact = get_object_or_404(Artifact, slug=slug)

    # Process video URL for embedding (YouTube/Vimeo)
    video_embed_url = None
    if artifact.video_url:
        video_embed_url = _get_embed_url(artifact.video_url)

    context = {
        'artifact': artifact,
        'video_embed_url': video_embed_url,
    }
    return render(request, 'artifacts/detail.html', context)


def _get_embed_url(url):
    """
    Convert a YouTube/Vimeo URL to an embeddable URL.
    
    Supports:
    - YouTube: youtube.com/watch?v=ID, youtu.be/ID
    - Vimeo: vimeo.com/ID
    """
    if not url:
        return None

    # YouTube
    if 'youtube.com/watch' in url:
        video_id = url.split('v=')[-1].split('&')[0]
        return f'https://www.youtube.com/embed/{video_id}'
    elif 'youtu.be/' in url:
        video_id = url.split('youtu.be/')[-1].split('?')[0]
        return f'https://www.youtube.com/embed/{video_id}'
    
    # Vimeo
    if 'vimeo.com/' in url:
        video_id = url.split('vimeo.com/')[-1].split('?')[0]
        return f'https://player.vimeo.com/video/{video_id}'

    # Return as-is if already an embed URL or unknown
    return url
