"""
Test settings for Griot 2.0.

Sets very high throttle limits so unit tests can run without hitting rate limits.

Use with:  DJANGO_SETTINGS_MODULE=config.settings.test
"""

from .base import *  # noqa: F401,F403

# Set very high throttle limits for tests (effectively disabled).
#
# IMPORTANT: build a NEW dict instead of mutating `REST_FRAMEWORK` in place.
# dev.py (and prod.py) do `from .base import *`, so they share the SAME dict
# object as base.py. The test runner's unittest discovery imports every
# `test*.py` module under the project (including this file) during an
# unlabelled `manage.py test` run; mutating the shared dict here would leak
# the 10000/min rates into dev/prod for the rest of the process. Reassigning
# the name keeps the override local to this module.
REST_FRAMEWORK = {  # noqa: F405
    **REST_FRAMEWORK,  # noqa: F405
    'DEFAULT_THROTTLE_RATES': {
        'anon': '10000/min',
        'user': '10000/min',
        'auth': '10000/min',
    },
}

# Use in-memory SQLite for faster tests.
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

# This is a settings module, not a test module — keep unittest discovery from
# loading it as one (the `test*.py` name pattern would otherwise match).
__test__ = False
