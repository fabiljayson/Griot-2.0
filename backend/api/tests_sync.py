"""
Tests for the sync_local_users management command.

Pushes accounts from the 'local' SQLite alias into the 'default' database,
de-duplicating by email. Both aliases are in-memory SQLite in tests.
"""
from io import StringIO

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import TransactionTestCase

User = get_user_model()


def _create_user(
    using,
    username,
    email,
    role='visitor',
    institution='',
    password='secret123',
):
    user = User(username=username, email=email, role=role, institution=institution)
    user.set_password(password)
    user.save(using=using)
    return user


def run_command(*args, **kwargs):
    out = StringIO()
    call_command('sync_local_users', *args, stdout=out, **kwargs)
    return out.getvalue()


class SyncLocalUsersCommandTests(TransactionTestCase):
    """Sync behaviour across two databases."""

    databases = {'default', 'local'}

    def setUp(self):
        self.local_admin = _create_user(
            'local',
            'local_admin',
            'la@test.com',
            role='admin',
            institution='Local Museum',
        )

    def test_pushes_new_users_into_target(self):
        run_command()

        created = User.objects.filter(email='la@test.com')
        self.assertEqual(created.count(), 1)
        pushed = created.get()
        self.assertEqual(pushed.role, 'admin')
        self.assertEqual(pushed.institution, 'Local Museum')
        # Password hash is copied verbatim so logins keep working.
        self.assertEqual(pushed.password, self.local_admin.password)

    def test_is_idempotent(self):
        run_command()
        self.assertEqual(User.objects.filter(email='la@test.com').count(), 1)
        run_command()
        self.assertEqual(User.objects.filter(email='la@test.com').count(), 1)

    def test_skips_users_already_present_by_email(self):
        _create_user('default', 'someone_else', 'la@test.com')

        output = run_command()
        self.assertIn('0 created', output)
        self.assertIn('1 already present (skipped)', output)
        self.assertEqual(User.objects.filter(email='la@test.com').count(), 1)

    def test_update_refreshes_matched_user(self):
        _create_user('default', 'someone_else', 'la@test.com')

        run_command()
        self.assertEqual(User.objects.get(email='la@test.com').role, 'visitor')

        run_command('--update')
        synced = User.objects.get(email='la@test.com')
        self.assertEqual(synced.role, 'admin')
        self.assertEqual(synced.institution, 'Local Museum')

    def test_username_collision_gets_unique_name(self):
        _create_user('default', 'local_admin', 'other@test.com')

        run_command()
        pushed = User.objects.get(email='la@test.com')
        self.assertNotEqual(pushed.username, 'local_admin')
        self.assertTrue(pushed.username.startswith('local_admin'))

    def test_dry_run_writes_nothing(self):
        output = run_command('--dry-run')

        self.assertEqual(User.objects.filter(email='la@test.com').count(), 0)
        self.assertIn('1 created (dry run)', output)

    def test_missing_source_alias_skips_gracefully(self):
        output = run_command('--source', 'nope')
        self.assertIn('No source database', output)


class SyncLocalMissingDatabaseTests(TransactionTestCase):
    """Behaviour when the 'local' SQLite file is absent (e.g. production)."""

    def test_absent_sqlite_file_skips(self):
        with self.settings(
            DATABASES={
                'default': {
                    'ENGINE': 'django.db.backends.sqlite3',
                    'NAME': ':memory:',
                },
                'local': {
                    'ENGINE': 'django.db.backends.sqlite3',
                    'NAME': '/nonexistent/griot_2.0/db.sqlite3',
                },
            }
        ):
            output = run_command()
            self.assertIn('No source database', output)