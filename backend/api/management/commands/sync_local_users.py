"""
Push users from the local SQLite database into the default (deployed) database.

Each local account is matched against the target by email (case-insensitive).
Accounts already present are left untouched unless --update is passed, which
refreshes name, role, institution and activity flags.

Usage:
    python manage.py sync_local_users                # local SQLite -> default
    python manage.py sync_local_users --dry-run      # preview only
    python manage.py sync_local_users --update       # also refresh matches

Works best from a dev machine: point 'default' at the hosted PostgreSQL via
DATABASE_URL, then run this to copy local accounts over. Password hashes are
copied verbatim, so already-registered users keep working after the move.
"""

from pathlib import Path

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

User = get_user_model()


class Command(BaseCommand):
    help = (
        'Copy users from the local SQLite database into the default database, '
        'de-duplicating by email.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--source',
            default='local',
            help='Database alias to read users from (default: local).',
        )
        parser.add_argument(
            '--target',
            default='default',
            help='Database alias to push users to (default: default).',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report what would change without writing anything.',
        )
        parser.add_argument(
            '--update',
            action='store_true',
            help='Refresh name/role/institution of users already in the target.',
        )

    def handle(self, *args, **options):
        source = options['source']
        target = options['target']
        dry_run = options['dry_run']

        if not self._database_available(source):
            self.stdout.write(
                self.style.WARNING(
                    f'No source database "{source}" available on this machine; '
                    'nothing to sync. Run from the machine holding db.sqlite3 '
                    'with the app configured to use it.'
                )
            )
            return

        local_users = list(User.objects.using(source).order_by('id'))
        existing_users = list(User.objects.using(target).all())
        existing_by_email = {
            (user.email or '').strip().lower(): user
            for user in existing_users
            if user.email
        }
        existing_by_username = {user.username for user in existing_users}

        created, updated, skipped = [], [], []
        for local in local_users:
            email_key = (local.email or '').strip().lower()

            if email_key and email_key in existing_by_email:
                match = existing_by_email[email_key]
                if options['update']:
                    self._apply_editable_fields(match, local)
                    if not dry_run:
                        match.save(using=target)
                    updated.append(local.username)
                else:
                    skipped.append(local.username)
                continue

            username = self._unique_username(
                local.username, existing_by_username
            )
            if dry_run:
                created.append(f'{local.username} → {username}')
                continue

            user = User(
                username=username,
                email=local.email,
                first_name=local.first_name,
                last_name=local.last_name,
                # Copy the existing hash verbatim so logins keep working.
                password=local.password,
                is_active=local.is_active,
                is_staff=local.is_staff,
                is_superuser=local.is_superuser,
                date_joined=local.date_joined,
                role=local.role,
                institution=local.institution,
            )
            user.save(using=target)
            existing_by_email[email_key] = user
            existing_by_username.add(user.username)
            created.append(local.username)

        self.stdout.write(
            self.style.MIGRATE_HEADING(
                f'{source} → {target}: '
                f'{len(local_users)} frontend user(s) considered'
            )
        )
        self.stdout.write(
            self.style.SUCCESS(f'  {len(created)} created' + (' (dry run)' if dry_run else ''))
        )
        self.stdout.write(f'  {len(updated)} updated')
        self.stdout.write(f'  {len(skipped)} already present (skipped)')

    def _database_available(self, alias: str) -> bool:
        config = settings.DATABASES.get(alias)
        if not config:
            return False
        engine = config.get('ENGINE', '')
        name = config.get('NAME')
        if engine.endswith('sqlite3') and isinstance(name, (str, Path)):
            # In-memory DBs (dev/tests) are always reachable.
            if name == ':memory:' or str(name).startswith('file:memorydb'):
                return True
            if not Path(name).exists():
                return False
        return True

    def _apply_editable_fields(self, target, source):
        target.first_name = source.first_name
        target.last_name = source.last_name
        target.role = source.role
        target.institution = source.institution
        target.is_active = source.is_active

    def _unique_username(self, base: str, taken: set) -> str:
        if base not in taken:
            return base
        suffix = 1
        candidate = f'{base}_{suffix}'
        while candidate in taken:
            suffix += 1
            candidate = f'{base}_{suffix}'
        return candidate