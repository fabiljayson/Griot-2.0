"""
Settings-level tests for feature 001 (retire artifacts app, scope hosts).

Pins the configuration contract from specs/001-retire-artifacts-app/
contracts/urls.md C5 and spec FR-003/FR-005/FR-006/FR-008:

- dev: no wildcard; only the four legitimate dev/tunnel hosts.
- test: explicit testserver/localhost/loopback (Django test client needs
  'testserver').
- prod: host sourcing stays env-driven (verified by reading the module
  source — prod cannot be imported at test time because it fail-fasts
  without DJANGO_SECRET_KEY).
- 'artifacts' app unregistered; its migration history remains on disk.

Note: the suite runs under config.settings.test, so the ambient
`settings` object reflects test values only. Each settings module is
imported directly for its own assertions — importing a settings module
does not modify the active Django settings.
"""

import importlib
from pathlib import Path

from django.conf import settings
from django.test import TestCase

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


class DevHostScopingTests(TestCase):
    """US2: dev ALLOWED_HOSTS must not be a wildcard."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.dev = importlib.import_module('config.settings.dev')

    def test_dev_has_no_wildcard(self):
        self.assertNotIn('*', self.dev.ALLOWED_HOSTS)

    def test_dev_allows_only_legitimate_dev_hosts(self):
        self.assertEqual(
            sorted(self.dev.ALLOWED_HOSTS),
            sorted(['localhost', '127.0.0.1', '.ngrok-free.app', '.ngrok.io']),
        )


class TestHostScopingTests(TestCase):
    """US2: test settings must serve Django's test client host."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.test_settings = importlib.import_module('config.settings.test')

    def test_test_settings_allow_testserver(self):
        self.assertIn('testserver', self.test_settings.ALLOWED_HOSTS)

    def test_test_settings_allow_localhost_and_loopback(self):
        self.assertIn('localhost', self.test_settings.ALLOWED_HOSTS)
        self.assertIn('127.0.0.1', self.test_settings.ALLOWED_HOSTS)

    def test_active_settings_match_test_module(self):
        """The runner's ambient settings agree with the test module."""
        self.assertIn('testserver', settings.ALLOWED_HOSTS)


class ArtifactsAppRetirementTests(TestCase):
    """US1/FR-003/FR-008: app unregistered, migration history kept."""

    def test_artifacts_app_unregistered(self):
        self.assertNotIn('artifacts', settings.INSTALLED_APPS)

    def test_artifacts_migrations_preserved_on_disk(self):
        migrations_dir = REPO_ROOT / 'artifacts' / 'migrations'
        self.assertTrue(migrations_dir.is_dir())
        migration_files = list(migrations_dir.glob('0*.py'))
        self.assertGreaterEqual(
            len(migration_files), 3,
            'artifacts/migrations history must not be deleted (FR-008)',
        )


class ProdHostSourcingTests(TestCase):
    """FR-006: prod sourcing untouched (source-level assertion)."""

    def test_prod_hosts_still_env_sourced(self):
        prod_source = (REPO_ROOT / 'config' / 'settings' / 'prod.py').read_text()
        self.assertIn("os.environ.get('DJANGO_ALLOWED_HOSTS')", prod_source)
        self.assertIn('RENDER_EXTERNAL_HOSTNAME', prod_source)
        # The old wildcard pattern must not have been introduced anywhere.
        self.assertNotIn("'*'", prod_source)

    def test_dev_module_source_has_no_wildcard_literal(self):
        dev_source = (REPO_ROOT / 'config' / 'settings' / 'dev.py').read_text()
        self.assertNotIn("'*'", dev_source)
