"""
Base Django settings for the Griot 2.0 / African Teller backend.

Shared by all environments (dev, prod). Environment-specific overrides
live in config.settings.dev and config.settings.prod.
"""

import os
import secrets
import sys
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent.parent

# Load environment variables from backend/.env if present (dev convenience).
load_dotenv(BASE_DIR / '.env')

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
# SECURITY WARNING: keep the secret key used in production secret!
#
# No committed fallback. This repository is public, so a literal here is a
# working forgery key (sessions, password-reset tokens, signed cookies) for
# every deployment that runs without DJANGO_SECRET_KEY. Without the env var,
# each process gets a random key instead: dev/test keep working (dev.py pins
# its own stable local key), while a misconfigured deployment fails loudly —
# sessions reset on restart — rather than silently accepting forged signatures
# made with a key from git history. config.settings.prod refuses to start
# without an explicit DJANGO_SECRET_KEY on top of this.
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY') or secrets.token_urlsafe(50)

DEBUG = False

ALLOWED_HOSTS = os.environ.get('DJANGO_ALLOWED_HOSTS', '').split(',')

# Proxies whose `X-Forwarded-For` header is believed. `X-Forwarded-For` is a
# plain request header, so a value is only honoured when the socket peer is one
# of these addresses; otherwise a client could write any IP into the scan and
# view analytics. Empty by default — the transport-level `REMOTE_ADDR` is the
# real peer and is used as-is. Comma-separated.
TRUSTED_PROXY_IPS = [
    ip.strip() for ip in os.environ.get('DJANGO_TRUSTED_PROXY_IPS', '').split(',')
    if ip.strip()
]

# ---------------------------------------------------------------------------
# Application definition
# ---------------------------------------------------------------------------
DJANGO_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

THIRD_PARTY_APPS = [
    'rest_framework',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'drf_spectacular',
]

# Modular Griot 2.0 apps (feature-first architecture)
LOCAL_APPS = [
    'users',
    'stories',
    'qr_codes',
    'gamification',
    'notifications',
    'media_app',
    # VR experiences: the launch-token handoff to the Unity application, and
    # the session rows progress is recorded against (feature 003).
    'vr',
    # Griot AI: grounded question answering for the app, the web UI and VR.
    'griot_ai',
    'heritage_crawl',
    'api',
    'web',
    # 'artifacts' retired (feature 001): was consolidated into qr_codes.
    # Its migration history remains on disk under artifacts/migrations/ —
    # do not delete while deployed databases reference it.
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    # Phase 5 Track A. This one line is the difference between a language
    # switch that works and one that only changes a URL parameter: without it
    # no request ever *has* a language, so every setting in the i18n block
    # below is decorative. It has to sit after SessionMiddleware (that is where
    # the chosen language is read from) and before CommonMiddleware (which
    # resolves the current URL).
    'django.middleware.locale.LocaleMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    # Phase 5 Track A. After AuthenticationMiddleware because it reads
    # request.user, and after LocaleMiddleware because it is that middleware's
    # saved answer this one fills in — it copies the reader's stored
    # preference into the session so the choice follows them to a new browser.
    'web.middleware.WebUserSettingsMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    # Phase 10 observability: one structured JSON log line per request.
    'api.middleware.RequestLogMiddleware',
]

ROOT_URLCONF = 'config.urls'

# Custom user model with Visitor/Contributor/InstitutionManager/Admin roles
# (Phase 2.1).
AUTH_USER_MODEL = 'users.User'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'web.context_processors.web_globals',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'

# ---------------------------------------------------------------------------
# Database (SQLite per Phase 1 spec; swap ENGINE in prod for Postgres later)
#
# Two aliases:
#   - 'default'   — the environment's primary database (SQLite in dev, the
#                   deployed PostgreSQL in prod when DATABASE_URL is set).
#   - 'local'     — always the repository SQLite file. Used by
#                   `sync_local_users` to push local accounts into the
#                   deployed database.
# ---------------------------------------------------------------------------
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    },
    'local': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    },
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
# Two security controls in this project are cache-backed, and both silently
# stop working when the cache is per-process:
#
#   1. Every DRF throttle (the 5/min auth budget, the 10/min metrics budget)
#      and every `config.rate_limit` web decorator. LocMemCache is private to
#      one gunicorn worker, so `--workers N` multiplies the real allowance by
#      N and an attacker just spreads requests across workers.
#   2. `rest_framework_simplejwt.token_blacklist`, which is what makes
#      ROTATE_REFRESH_TOKENS + BLACKLIST_AFTER_ROTATION mean anything. A
#      blacklisted refresh token stays valid in any worker that never saw the
#      blacklist write, so logout and rotation can be undone by retrying
#      against a different worker.
#
# Set REDIS_URL to fix both. Left unset, this falls back to LocMemCache so a
# laptop needs no extra service — and says so loudly in production, because
# that fallback is correct on a single-worker deploy and wrong on every other.
REDIS_URL = os.environ.get('REDIS_URL', '').strip()

if REDIS_URL:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.redis.RedisCache',
            'LOCATION': REDIS_URL,
            # Throttle windows here are 60s; a socket timeout longer than that
            # would let a stalled Redis turn a rate limit into a hang.
            'OPTIONS': {
                'socket_connect_timeout': 2,
                'socket_timeout': 2,
            },
            'KEY_PREFIX': 'griot',
        }
    }
else:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
            'LOCATION': 'griot-default',
        }
    }
    if not DEBUG:
        # `manage.py migrate` at start-up and every management command import
        # these settings, so keep this to one line rather than a traceback.
        print(
            'WARNING: REDIS_URL is unset, so rate limits and the JWT '
            'blacklist are using a per-process LocMemCache. Both are only '
            'exact on a single-worker deployment. Set REDIS_URL before '
            'scaling gunicorn workers.',
            file=sys.stderr,
        )

# ---------------------------------------------------------------------------
# Password validation
# ---------------------------------------------------------------------------
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ---------------------------------------------------------------------------
# Django REST Framework
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    'DEFAULT_RENDERER_CLASSES': [
        'rest_framework.renderers.JSONRenderer',
    ],
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticatedOrReadOnly',
    ],
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 20,
    # Strict throttling (Phase 2.1): auth endpoints limited to 5 requests
    # per minute per IP; general API traffic throttled as well.
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '120/min',   # general anonymous API traffic
        'user': '600/min',   # authenticated API traffic
        'auth': '5/min',     # auth endpoints (login, register, refresh)
        # Unauthenticated metrics: six COUNT() queries per hit, so it gets its
        # own budget rather than sharing the general anonymous one.
        'metrics': '10/min',
        # VR launch runs on the phone and mints a credential every time, so it
        # gets an auth-sized budget rather than the general one: a reader taps
        # this button a handful of times, a script does not.
        'vr_launch': '10/min',
        # The exchange endpoint is unauthenticated — the launch token is the
        # credential — so its budget is per IP and has to assume a hostile
        # caller guessing tokens into it.
        'vr_token': '20/min',
        # Ask Griot spends real LLM tokens per request.
        'ai_ask': '10/min',
    },
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
    # Turns a unique-constraint collision into a 400 instead of an opaque 500.
    'EXCEPTION_HANDLER': 'config.exception_handler.api_exception_handler',
}

# --- drf-spectacular (OpenAPI 3.0 schema) ---
SPECTACULAR_SETTINGS = {
    'TITLE': 'Griot 2.0 API',
    'DESCRIPTION': 'African Teller digital heritage platform — stories, artifacts, gamification, and media generation.',
    'VERSION': '0.2.0',
    'SERVE_INCLUDE_SCHEMA': False,
    'SCHEMA_PATH_PREFIX': r'/api/',
    # Several models each define a `Status` and a `Category` choice set, so
    # drf-spectacular cannot derive a unique component name from the field
    # alone and falls back to hash-suffixed names ("Status244Enum"). Those
    # names are stable-ish but meaningless to a client reading the schema, and
    # they change whenever an unrelated field is added.
    #
    # The values point at module-level aliases (`StoryStatusChoices`, etc.)
    # rather than the nested classes, because ENUM_NAME_OVERRIDES resolves each
    # value with `import_string`, which cannot walk into a class. See the alias
    # block at the bottom of stories/models.py.
    'ENUM_NAME_OVERRIDES': {
        'StoryStatusEnum': 'stories.models.StoryStatusChoices.choices',
        # `Story.licence` and `CrawlSource.default_licence` carry the identical
        # choice set, so spectacular derived a name for each and reported
        # `W001: multiple names for the same choice set (LicenceEnum)`. It was
        # introduced when the crawler added `default_licence`. Pinning one name
        # for both fields is the same fix the other entries in this block use.
        'LicenceEnum': 'stories.models.StoryLicenceChoices.choices',
        'QuizAttemptStatusEnum': 'gamification.models.QuizAttemptStatusChoices.choices',
        # VideoGenerationJob.Status and AudioNarrationJob.Status hold identical
        # values, so they deliberately share one name — two names for one set is
        # an error, not a feature.
        'MediaJobStatusEnum': 'media_app.models.MediaJobStatusChoices.choices',
        'BadgeCategoryEnum': 'gamification.models.BadgeCategoryChoices.choices',
        'ArtifactCategoryEnum': 'qr_codes.models.ArtifactCategoryChoices.choices',
        'VRCompletionStatusEnum': 'vr.models.VRCompletionStatusChoices.choices',
        'GriotMessageRoleEnum': 'griot_ai.models.GriotMessageRoleChoices.choices',
        # Pinned in Phase 5 Track A. `role` is the one remaining choice set
        # that had no entry, and wrapping its labels in `gettext_lazy` was
        # enough to change the hash spectacular appends to the auto-generated
        # name, which turned it into `Role017Enum` and tripped the
        # collision warning. The names are unstable by construction, so the
        # fix is to stop deriving them.
        'UserRoleEnum': 'users.models.UserRole.choices',
    },
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=30),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
}

# ---------------------------------------------------------------------------
# Internationalization (Phase 5 Track A)
# ---------------------------------------------------------------------------
# 'en' rather than 'en-us': the web preference (`WebUserSettings.language`),
# the `Language` codes in `Story` and the language switch all speak 'en', and
# a default language that is not itself in LANGUAGES makes every lookup fall
# back one step before it starts.
LANGUAGE_CODE = 'en'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

# The interface languages this project can actually render.
#
# Only languages with a compiled catalogue in `locale/` belong here. Adding a
# code without one produces the exact defect Phase 5 was opened to close: a
# language switch that offers a choice and then renders English anyway.
# Track B's AGLC languages (ewo/dua/bml) are deliberately absent — they are
# blocked on the font-stack decision (see docs/ROADMAP.md, Finding 2) and on a
# translator, not on this list. `LocaleCatalogTests` fails if a code is ever
# added here without a catalogue behind it.
LANGUAGES = [
    ('en', 'English'),
    ('fr', 'Français'),
]

# Project catalogues. Django's own admin/validation translations ship inside
# the venv and are found automatically; these are ours.
LOCALE_PATHS = [BASE_DIR / 'locale']

# ---------------------------------------------------------------------------
# Logging (Phase 10 observability)
# ---------------------------------------------------------------------------
# All loggers emit structured single-line JSON to stdout/stderr so they can
# be aggregated and searched without additional parsing.
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'api.logging.JsonFormatter',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'json',
        },
    },
    'root': {
        'handlers': ['console'],
        # WARNING at root keeps third-party library noise out of the JSON
        # stream; app loggers (django, api.request) set their own levels.
        'level': 'WARNING',
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': os.environ.get('DJANGO_LOG_LEVEL', 'INFO'),
            'propagate': False,
        },
        'api.request': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

# ---------------------------------------------------------------------------
# Static files (CSS, JavaScript, Images)
# ---------------------------------------------------------------------------
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Project static assets (compiled Tailwind CSS, self-hosted fonts, Font
# Awesome). App static dirs are discovered automatically by staticfiles.
STATICFILES_DIRS = [BASE_DIR / 'static']

# Serve everything locally (fonts, CSS, icons) — no CDN / external network.
# WhiteNoise (if installed) compresses and serves these efficiently in prod;
# it must sit directly after SecurityMiddleware.
try:
    import whitenoise  # noqa: F401

    if 'whitenoise.middleware.WhiteNoiseMiddleware' not in MIDDLEWARE:
        MIDDLEWARE.insert(
            1, 'whitenoise.middleware.WhiteNoiseMiddleware')
except ImportError:
    pass

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ---------------------------------------------------------------------------
# Site URL (used by QR codes, deep links, and share URLs)
# ---------------------------------------------------------------------------
SITE_URL = os.environ.get('SITE_URL', 'https://africanteller.org')
DEEP_LINK_BASE_URL = os.environ.get('DEEP_LINK_BASE_URL', SITE_URL)

# ---------------------------------------------------------------------------
# Web interface (server-rendered, session-based)
# ---------------------------------------------------------------------------
LOGIN_URL = '/accounts/login/'
LOGIN_REDIRECT_URL = '/'
LOGOUT_REDIRECT_URL = '/'

# ---------------------------------------------------------------------------
# AI media generation (gTTS narration, Luma Dream Machine video)
# ---------------------------------------------------------------------------
# Luma bills per generation, so the key is read from the environment rather
# than hardcoded. When it is absent `get_luma_service()` returns the mock
# service, which keeps local dev and tests working without external calls.
LUMA_API_KEY = os.environ.get('LUMA_API_KEY', '')

# Whether the mock is allowed to stand in for the real service.
#
# The mock marks jobs 'completed' and hands back a
# https://storage.example.com/... URL that plays nothing. On a laptop that is
# a useful placeholder. In production it is worse than a hard failure: the
# dashboard says the video is done, the row is marked complete, the daily
# quota was spent, and the user gets an unplayable player with no indication
# anything went wrong. So outside DEBUG the mock refuses to load and the
# request fails loudly instead. Set LUMA_ALLOW_MOCK=1 to override (a staging
# deploy that deliberately wants fake data).
_LUMA_ALLOW_MOCK_RAW = os.environ.get('LUMA_ALLOW_MOCK')
LUMA_ALLOW_MOCK = (
    DEBUG
    if _LUMA_ALLOW_MOCK_RAW is None
    else _LUMA_ALLOW_MOCK_RAW.strip().lower() in ('1', 'true', 'yes', 'on')
)

# Bound spend: how many video jobs one user may start per day. The cap is
# applied on top of the ownership rule so a wide-open policy cannot be
# farmed for free renders.
VIDEO_GENERATIONS_PER_USER_PER_DAY = int(
    os.environ.get('VIDEO_GENERATIONS_PER_USER_PER_DAY', '5')
)

# The same bound for audio narration, which is not billed per call but is not
# free either: each job is a synchronous request out to Google Translate's
# public TTS endpoint plus an MP3 written to MEDIA_ROOT. Left uncapped, the
# general API throttle (600 requests/minute) is all that stands between one
# account and several GB of audio, and between this deployment and being cut
# off from an endpoint we do not pay for. Cached narrations are reused before
# this cap is consulted, so re-reading a story never costs quota.
AUDIO_NARRATIONS_PER_USER_PER_DAY = int(
    os.environ.get('AUDIO_NARRATIONS_PER_USER_PER_DAY', '10')
)

# Budget for the server-rendered web login and registration forms. DRF's
# throttle rates do not reach plain Django views, so these two endpoints were
# unthrottled while the API's `auth` scope was capped at 5/min. Kept as a
# separate setting (rather than reusing the DRF dict) because the two are
# enforced by different machinery: see config/rate_limit.py.
WEB_AUTH_ATTEMPTS_PER_MIN = int(
    os.environ.get('WEB_AUTH_ATTEMPTS_PER_MIN', '5')
)

# Artifact view scans are a read-path side effect. One row per viewer per window
# is enough signal for engagement analytics, so a reload loop or crawler cannot
# inflate the count or grow the table unboundedly. The trade-off is deliberate:
# a genuinely repeat-viewing user inside the window is folded into the earlier
# scan rather than logged twice.
SCAN_DEDUPE_WINDOW_SECONDS = int(
    os.environ.get('SCAN_DEDUPE_WINDOW_SECONDS', '3600')
)

# ---------------------------------------------------------------------------
# Griot AI (grounded question answering)
# ---------------------------------------------------------------------------
# Provider key. Read from the environment and never sent to a client: Flutter,
# the web UI and Unity all reach the model through `/api/ai/ask/` on this server.
GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')

# Provider model id. Configurable because model ids are added and retired on the
# provider's schedule; pinning one in source turns a deprecation into a release.
GRIOT_AI_MODEL = os.environ.get('GRIOT_AI_MODEL', 'gemini-2.5-flash')
GRIOT_AI_BASE_URL = os.environ.get(
    'GRIOT_AI_BASE_URL', 'https://generativelanguage.googleapis.com'
)
GRIOT_AI_TIMEOUT_SECONDS = float(os.environ.get('GRIOT_AI_TIMEOUT_SECONDS', '30'))
GRIOT_AI_MAX_OUTPUT_TOKENS = int(os.environ.get('GRIOT_AI_MAX_OUTPUT_TOKENS', '800'))

# Character budget for the retrieved context handed to the model. Bounds both
# the per-question cost and how much of a long story can crowd out the artifact
# the reader is actually looking at.
GRIOT_AI_MAX_CONTEXT_CHARS = int(
    os.environ.get('GRIOT_AI_MAX_CONTEXT_CHARS', '6000')
)

# Whether the mock may stand in for the real model. Same reasoning as
# LUMA_ALLOW_MOCK: the mock answers in "development mode" prose, which is worse
# than an outage in production because it looks like a working feature.
_GRIOT_ALLOW_MOCK_RAW = os.environ.get('GRIOT_AI_ALLOW_MOCK')
GRIOT_AI_ALLOW_MOCK = (
    DEBUG
    if _GRIOT_ALLOW_MOCK_RAW is None
    else _GRIOT_ALLOW_MOCK_RAW.strip().lower() in ('1', 'true', 'yes', 'on')
)

# Rolling 24-hour ceiling on questions that reach the provider, per account.
# Each answer costs real tokens, so this is the bound that stops one account
# from spending the deployment's budget.
AI_ASKS_PER_USER_PER_DAY = int(
    os.environ.get('AI_ASKS_PER_USER_PER_DAY', '40')
)

# ---------------------------------------------------------------------------
# VR (Unity) handoff
# ---------------------------------------------------------------------------
# Scheme and host of the deep link Flutter hands to Android. It lives in
# settings rather than in the Flutter app alone so the link the API returns and
# the intent filter the Unity build declares are compared against one value in
# code review, instead of two hardcoded strings in two repositories.
VR_DEEP_LINK_SCHEME = os.environ.get('VR_DEEP_LINK_SCHEME', 'griotvr')
VR_DEEP_LINK_HOST = os.environ.get('VR_DEEP_LINK_HOST', 'launch')

# How long a launch token stays usable. The reader's phone creates it and the
# headset consumes it seconds later, so anything generous here is pure attack
# surface: the token travels through an Android intent any app can observe.
VR_LAUNCH_TOKEN_TTL_SECONDS = int(
    os.environ.get('VR_LAUNCH_TOKEN_TTL_SECONDS', '120')
)

# Lifetime of the VR-scoped JWT the exchange returns. Short because it is a
# bearer token on a device we cannot attest, and because there is no refresh
# token: when it lapses, the reader taps "Explore in VR" again.
VR_SESSION_TOKEN_MINUTES = int(os.environ.get('VR_SESSION_TOKEN_MINUTES', '45'))

# XP paid for a completed experience, handed to the existing gamification
# profile. Zero disables the award without touching the session bookkeeping.
VR_SESSION_XP_COMPLETE = int(os.environ.get('VR_SESSION_XP_COMPLETE', '25'))

# gTTS talks to Google Translate's public endpoint over `requests`, which
# exposes no timeout knob of its own. These bound the call so a hung socket
# cannot pin a worker forever.
TTS_MAX_CHARS = int(os.environ.get('TTS_MAX_CHARS', '3000'))
TTS_SOCKET_TIMEOUT = float(os.environ.get('TTS_SOCKET_TIMEOUT', '20'))
