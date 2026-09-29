"""
Tests for the config.safety guard that keeps demo seeders off hosted databases.

The security contract: `seed_users` / `seed_all` may only run under an
allow-listed settings module, and a password that is public in this repository
is never accepted outside a developer machine.
"""

from io import StringIO

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase, override_settings

from config.safety import (
    INSECURE_DEFAULT_PASSWORD,
    assert_safe_environment,
    is_production,
    require_explicit_password,
)

User = get_user_model()

PROD = 'config.settings.prod'
DEV = 'config.settings.dev'


def run_command(*args, **kwargs):
    out = StringIO()
    call_command('seed_users', *args, stdout=out, stderr=StringIO(), **kwargs)
    return out.getvalue()


class IsProductionTests(SimpleTestCase):
    @override_settings(SETTINGS_MODULE=PROD)
    def test_prod_is_production(self):
        self.assertTrue(is_production())

    @override_settings(SETTINGS_MODULE='config.settings.base')
    def test_unknown_module_fails_closed(self):
        # An unlisted module is treated as production until someone adds it.
        self.assertTrue(is_production())

    @override_settings(SETTINGS_MODULE=DEV)
    def test_dev_is_not_production(self):
        self.assertFalse(is_production())

    @override_settings(SETTINGS_MODULE='config.settings.test')
    def test_test_is_not_production(self):
        self.assertFalse(is_production())


class AssertSafeEnvironmentTests(SimpleTestCase):
    @override_settings(SETTINGS_MODULE=DEV)
    def test_allows_dev(self):
        assert_safe_environment('seed_users', reason='because')

    @override_settings(SETTINGS_MODULE=PROD)
    def test_refuses_prod(self):
        with self.assertRaises(CommandError) as ctx:
            assert_safe_environment('seed_users', reason='known-password admin')
        self.assertIn('seed_users', str(ctx.exception))
        self.assertIn('known-password admin', str(ctx.exception))


class RequireExplicitPasswordTests(SimpleTestCase):
    def test_refuses_missing(self):
        with self.assertRaises(CommandError):
            require_explicit_password('seed_users', None)

    def test_refuses_the_published_demo_password(self):
        with self.assertRaises(CommandError) as ctx:
            require_explicit_password('seed_users', INSECURE_DEFAULT_PASSWORD)
        self.assertIn('well-known demo password', str(ctx.exception))

    def test_accepts_a_real_password(self):
        self.assertEqual(
            require_explicit_password('seed_users', 'a-real-one'),
            'a-real-one',
        )


class SeedUsersGuardTests(SimpleTestCase):
    """End-to-end: the command itself must refuse on a hosted database."""

    def test_seed_users_refuses_under_prod_settings(self):
        with override_settings(SETTINGS_MODULE=PROD):
            with self.assertRaises(CommandError) as ctx:
                run_command()
        self.assertIn('Refusing to run "seed_users"', str(ctx.exception))

    def test_seed_users_refuses_published_password_under_prod(self):
        with override_settings(SETTINGS_MODULE=PROD):
            with self.assertRaises(CommandError):
                run_command('--password', INSECURE_DEFAULT_PASSWORD)


class SeedAllGuardTests(SimpleTestCase):
    def test_seed_all_refuses_under_prod_settings(self):
        with override_settings(SETTINGS_MODULE=PROD):
            with self.assertRaises(CommandError) as ctx:
                call_command('seed_all', stdout=StringIO(), stderr=StringIO())
        self.assertIn('Refusing to run "seed_all"', str(ctx.exception))
