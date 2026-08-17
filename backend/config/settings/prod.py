"""
Production settings for Griot 2.0.

Usage:  DJANGO_SETTINGS_MODULE=config.settings.prod
Requires the environment variables below; fails fast if missing.
"""

import os

import dj_database_url
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

from .base import *  # noqa: F401,F403
from .base import SECRET_KEY, DATABASES

# Hard fail in production if required env vars are missing or insecure.
if not os.environ.get('DJANGO_SECRET_KEY'):
    raise RuntimeError('Missing required environment variables: DJANGO_SECRET_KEY')
if SECRET_KEY == 'django-insecure-dev-only-change-me':
    raise RuntimeError(
        'DJANGO_SECRET_KEY is set to the insecure development default. '
        'Refusing to run in production.'
    )

DEBUG = False

# Allowed hosts — DJANGO_ALLOWED_HOSTS wins; otherwise fall back to Render's
# automatically-injected RENDER_EXTERNAL_HOSTNAME so the Render Blueprint
# works with zero host config. (base.py already parsed DJANGO_ALLOWED_HOSTS;
# recompute here so the Render fallback applies.)
render_host = os.environ.get('RENDER_EXTERNAL_HOSTNAME')
allowed_hosts = os.environ.get('DJANGO_ALLOWED_HOSTS') or (render_host or '')
if not allowed_hosts:
    raise RuntimeError(
        'Missing required environment variables: DJANGO_ALLOWED_HOSTS '
        '(or set RENDER_EXTERNAL_HOSTNAME on Render)'
    )
ALLOWED_HOSTS = [host.strip() for host in allowed_hosts.split(',') if host.strip()]

# CORS for the hosted web client only. Defaults to https://<render-host> so
# the onrender.com subdomain is allowed out of the box.
cors_origins = os.environ.get('DJANGO_CORS_ORIGINS') or (
    f'https://{render_host}' if render_host else ''
)
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in cors_origins.split(',')
    if origin.strip()
]

# CSRF trusted origins mirror the CORS allow-list. JWT auth keeps most API
# traffic cookie-free, but Django admin and any session/cookie flows require
# these to be explicitly trusted.
CSRF_TRUSTED_ORIGINS = CORS_ALLOWED_ORIGINS

# HTTPS / security hardening.
SECURE_SSL_REDIRECT = os.environ.get('DJANGO_SECURE_SSL_REDIRECT', 'true').lower() == 'true'
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
# Strict Transport Security: one year with subdomains + preload by default
# (override DJANGO_HSTS_SECONDS to 0 to disable during an emergency rollout).
SECURE_HSTS_SECONDS = int(os.environ.get('DJANGO_HSTS_SECONDS', '31536000'))
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_REFERRER_POLICY = 'same-origin'

# Database — PostgreSQL when DATABASE_URL is set (e.g.
# postgres://user:password@host:5432/dbname). Falls back to the SQLite
# configured in base.py for small/single-instance deployments.
DATABASE_URL = os.environ.get('DATABASE_URL')
if DATABASE_URL:
    # Reassign the name (don't mutate) to keep the override local to prod.
    DATABASES = {
        'default': dj_database_url.parse(
            DATABASE_URL,
            conn_max_age=int(os.environ.get('DB_CONN_MAX_AGE', '600')),
            conn_health_checks=True,
        ),
    }

# Sentry error monitoring (Phase 10.1 baseline wired in from the start).
SENTRY_DSN = os.environ.get('SENTRY_DSN')
if SENTRY_DSN:
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[DjangoIntegration()],
        traces_sample_rate=0.2,
        environment='production',
    )
