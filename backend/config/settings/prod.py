"""
Production settings for Griot 2.0.

Usage:  DJANGO_SETTINGS_MODULE=config.settings.prod
Requires the environment variables below; fails fast if missing.
"""

import os

import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

from .base import *  # noqa: F401,F403
from .base import SECRET_KEY

# Hard fail in production if required env vars are missing or insecure.
required_env = [
    'DJANGO_SECRET_KEY',
    'DJANGO_ALLOWED_HOSTS',
]
missing = [var for var in required_env if not os.environ.get(var)]
if missing:
    raise RuntimeError(f'Missing required environment variables: {", ".join(missing)}')
if SECRET_KEY == 'django-insecure-dev-only-change-me':
    raise RuntimeError(
        'DJANGO_SECRET_KEY is set to the insecure development default. '
        'Refusing to run in production.'
    )

DEBUG = False

# CORS for the hosted web client only.
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get('DJANGO_CORS_ORIGINS', '').split(',')
    if origin.strip()
]

# HTTPS / security hardening.
SECURE_SSL_REDIRECT = os.environ.get('DJANGO_SECURE_SSL_REDIRECT', 'true').lower() == 'true'
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# Sentry error monitoring (Phase 10.1 baseline wired in from the start).
SENTRY_DSN = os.environ.get('SENTRY_DSN')
if SENTRY_DSN:
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[DjangoIntegration()],
        traces_sample_rate=0.2,
        environment='production',
    )
