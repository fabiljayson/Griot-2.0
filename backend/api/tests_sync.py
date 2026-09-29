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
        # Profile fields carry across so the account is recognisable...
        self.assertEqual(pushed.institution, 'Local Museum')
        # ...but the role does not. A developer database routinely holds an
        # admin row created by a seeder; copying it would hand out the
        # platform's moderation and analytics surface.
        self.assertEqual(pushed.role, 'visitor')
        # Password hash is copied verbatim so logins keep working.
        self.assertEqual(pushed.password, self.local_admin.password)

    def test_never_copies_privilege_flags(self):
        local_admin = User.objects.using('local').get(username='local_admin')
        local_admin.is_staff = True
        local_admin.is_superuser = True
        local_admin.save(using='local')

        run_command()

        pushed = User.objects.get(email='la@test.com')
        self.assertFalse(pushed.is_staff)
        self.assertFalse(pushed.is_superuser)
        self.assertEqual(pushed.role, 'visitor')

    def test_update_does_not_escalate_privileges(self):
        _create_user('default', 'someone_else', 'la@test.com')
        User.objects.filter(email='la@test.com').update(is_superuser=True)

        run_command('--update')

        synced = User.objects.get(email='la@test.com')
        self.assertEqual(synced.institution, 'Local Museum')
        # --update refreshes the profile only; it cannot promote the account.
        self.assertEqual(synced.role, 'visitor')
        self.assertTrue(synced.is_superuser)

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

class SyncLocalUsersPasswordHashTests(TransactionTestCase):
    """A weak or unrecognised source hash must not reach the target.

    The command used to copy `password` verbatim. The source is a developer
    SQLite file, so that value can be a raw MD5 digest, the unusable marker, or
    empty — none of which are acceptable credentials in production. A copied
    MD5 is offline-crackable in seconds, and an empty/`!` value means "any
    password works" on a code path that only looks like a data migration.
    """

    databases = {'default', 'local'}

    def _local_with_raw_hash(self, username, raw_hash):
        """Insert a user whose password column holds [raw_hash] verbatim."""
        User.objects.using('local').create(
            username=username,
            email=f'{username}@test.com',
            password=raw_hash,
        )

    def _synced(self, username):
        return User.objects.get(username=username)

    def test_strong_hash_is_copied_so_logins_keep_working(self):
        good = User(username='good', email='good@test.com')
        good.set_password('secret123')
        good.save(using='local')

        run_command()

        pushed = self._synced('good')
        self.assertTrue(pushed.check_password('secret123'))

    def test_raw_md5_digest_is_not_copied(self):
        # md5('password') — a bare digest that identify_hasher rejects.
        self._local_with_raw_hash('weak', '5f4dcc3b5aa765d61d8327deb882cf99')

        run_command()

        pushed = self._synced('weak')
        self.assertFalse(pushed.has_usable_password())
        self.assertFalse(pushed.check_password('password'))

    def test_unusable_marker_is_not_copied(self):
        self._local_with_raw_hash('marker', '!not-a-real-hash')

        run_command()

        self.assertFalse(self._synced('marker').has_usable_password())

    def test_empty_password_is_not_copied(self):
        self._local_with_raw_hash('empty', '')

        run_command()

        self.assertFalse(self._synced('empty').has_usable_password())

    def test_account_is_still_created_so_history_is_preserved(self):
        """The user must exist; only the credential is withheld.

        Dropping the row would also delete the account's stories, quiz attempts
        and gamification, which is a far worse outcome than a forced reset.
        """
        self._local_with_raw_hash('weak', '5f4dcc3b5aa765d61d8327deb882cf99')

        run_command()

        self.assertTrue(User.objects.filter(username='weak').exists())

    def test_weak_hash_accounts_are_reported(self):
        self._local_with_raw_hash('weak', '5f4dcc3b5aa765d61d8327deb882cf99')

        output = run_command()

        self.assertIn('without a usable password', output)
        self.assertIn('weak', output)

    def test_dry_run_reports_reset_accounts_without_writing(self):
        self._local_with_raw_hash('weak', '5f4dcc3b5aa765d61d8327deb882cf99')

        output = run_command('--dry-run')

        self.assertIn('without a usable password', output)
        self.assertFalse(User.objects.filter(username='weak').exists())

    def test_privileges_are_still_never_copied_on_the_hash_path(self):
        """The password fix must not have loosened the existing guard."""
        User.objects.using('local').create(
            username='local_admin',
            email='la@test.com',
            password='5f4dcc3b5aa765d61d8327deb882cf99',
            role='admin',
            is_staff=True,
            is_superuser=True,
        )

        run_command()

        pushed = User.objects.get(email='la@test.com')
        self.assertFalse(pushed.is_staff)
        self.assertFalse(pushed.is_superuser)
        self.assertFalse(pushed.has_usable_password())
