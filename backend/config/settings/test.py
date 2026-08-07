"""
Test settings for Griot 2.0.

Sets very high throttle limits so unit tests can run without hitting rate limits.
"""

from .base import *  # noqa: F401,F403

# Set very high throttle limits for tests (effectively disabled).
REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'] = {  # noqa: F405
    'anon': '10000/min',
    'user': '10000/min',
    'auth': '10000/min',
}

# Use in-memory SQLite for faster tests.
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}
