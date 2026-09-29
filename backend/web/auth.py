"""
Authentication helpers for the server-rendered web interface.

The web UI uses Django sessions (cookies) while the mobile app uses JWT.
Both authenticate against the same `users.User` model, so data structures
stay identical across platforms.
"""

# Where to send users after login when no ?next= is present.
DEFAULT_LOGIN_REDIRECT = 'web:home'
