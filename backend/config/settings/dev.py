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

ALLOWED_HOSTS = ['*']

# CORS: allow the Flutter web/PWA dev server and mobile emulators.
CORS_ALLOW_ALL_ORIGINS = True

# Serve media files in development via Django.
STATICFILES_DIRS = [BASE_DIR / 'static']

# SQLite already configured in base.py — keep it for local dev.
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}
