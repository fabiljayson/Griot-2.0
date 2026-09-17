"""
Authentication helpers for the server-rendered web interface.

The web UI uses Django sessions (cookies) while the mobile app uses JWT.
Both authenticate against the same `users.User` model, so data structures
stay identical across platforms.
"""

from django.contrib.auth import REDIRECT_FIELD_NAME

# Where to send users after login when no ?next= is present.
DEFAULT_LOGIN_REDIRECT = 'web:home'


def login_redirect_url(request) -> str:
    """Resolve the post-login redirect target from the request."""
    next_url = request.POST.get(
        REDIRECT_FIELD_NAME,
        request.GET.get(REDIRECT_FIELD_NAME, ''),
    )
    return next_url or DEFAULT_LOGIN_REDIRECT
