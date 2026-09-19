"""
Development settings for Griot 2.0.

Usage:  DJANGO_SETTINGS_MODULE=config.settings.dev
Default for local `manage.py` commands.
"""

from .base import *  # noqa: F401,F403
from .base import BASE_DIR

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

SECRET_KEY = 'django-insecure-dev-only-change-me'

ALLOWED_HOSTS = [
    'localhost',
    '127.0.0.1',
    '.ngrok-free.app',
    '.ngrok.io',
    '*',
]

# CORS: allow the Flutter web/PWA dev server, mobile emulators, and ngrok.
CORS_ALLOW_ALL_ORIGINS = True

# Allow custom headers (Crucial for bypassing Ngrok free tier warning)
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
    'ngrok-skip-browser-warning',
]

# Serve media files in development via Django.
# (STATICFILES_DIRS now lives in base.py so prod collectstatic picks up the
# compiled Tailwind CSS, fonts, and Font Awesome assets.)

# SQLite already configured in base.py — keep it for local dev.
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}
