"""
Push users from the local SQLite database into the default (deployed) database.

Each local account is matched against the target by email (case-insensitive).
Accounts already present are left untouched unless --update is passed, which
refreshes name and institution.

Usage:
    python manage.py sync_local_users                # local SQLite -> default
    python manage.py sync_local_users --dry-run      # preview only
    python manage.py sync_local_users --update       # also refresh matches

Works best from a dev machine: point 'default' at the hosted PostgreSQL via
DATABASE_URL, then run this to copy local accounts over. Password hashes are
copied only when they are strong enough to be worth copying (see PASSWORDS
ARE NOT BLINDLY COPIED); everything else lands with an unusable password that
forces a reset.

PRIVILEGES ARE NEVER COPIED
`role`, `is_staff` and `is_superuser` are deliberately excluded. A developer
database is a low-trust source: it is routinely created by seeders that mint an
is_superuser admin, and by local experiments that flip role to test a screen.
Copying those rows would silently grant platform-wide or Django-admin access in
production. New accounts land as the default role with no staff rights, and
`--update` leaves the target's existing privileges untouched.

PASSWORDS ARE NOT BLINDLY COPIED
The source is a developer SQLite file, so its `password` column is whatever
that machine happened to write: a Django default PBKDF2 hash, a raw MD5 or
SHA-1 hash from a `check_password` shortcut, the unusable `!` marker, or an
empty string. Copying any of those into production propagates the weakness —
an MD5 hash is offline-crackable in seconds, and an empty or `!` value means
"any password is acceptable" on a path that only looks like a migration.

So each hash is inspected before it is used:

* A hash Django recognises **and** that is at least as strong as the weakest
  configured hasher is copied, so genuine accounts keep working.
* Anything else — unrecognised, unusable, weaker than configured, or empty — is
  replaced with `set_unusable_password()`. The account is created and the user
  is told to reset; the alternative is a weak credential in production.

The command reports how many fell into each bucket so the operator knows
exactly which accounts need a password reset before anyone tries to log in.
"""

from pathlib import Path

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import identify_hasher, is_password_usable
from django.core.management.base import BaseCommand

User = get_user_model()

#: Fields `--update` is allowed to refresh. Excludes every privilege flag.
_SYNCABLE_PROFILE_FIELDS = ('first_name', 'last_name', 'institution')


def is_hash_safe_to_copy(encoded: str) -> bool:
    """True when [encoded] may be written into the target database.

    Rejects, in order:
      * empty / missing values,
      * the unusable-password marker (`!…`), which accepts any password,
      * anything `identify_hasher` does not recognise, including a raw MD5 or
        SHA-1 digest that would be offline-cracked trivially,
      * a hash that is not one of the algorithms this deployment is configured
        to produce or accept. Django only ever *mints* the first entry in
        PASSWORD_HASHERS, so a hash of any other configured algorithm is
        accepted on sign-in but never re-issued and would not be rotated on a
        future upgrade — carrying one into production freezes it at whatever
        strength it had on the developer machine.
    """
    if not encoded or not isinstance(encoded, str):
        return False
    if not is_password_usable(encoded):
        return False
    try:
        hasher = identify_hasher(encoded)
    except ValueError:
        # Unrecognised format: a bare digest, or something not produced by
        # Django at all. Never propagate it.
        return False
    return hasher.algorithm == _preferred_hasher().algorithm


def _preferred_hasher():
    """The hasher Django would mint a new password with.

    That is the first entry of PASSWORD_HASHERS, and the only one that matters
    here: a hash from any weaker configured algorithm would still authenticate,
    but it would never be replaced by a stronger one automatically.
    """
    from django.contrib.auth.hashers import get_hasher

    return get_hasher()


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

        created, updated, skipped, needs_reset = [], [], [], []
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
            # Whether the source hash may be carried over is decided before the
            # dry-run branch so a preview tells the operator exactly which
            # accounts will need a password reset, not just which will exist.
            copy_password = is_hash_safe_to_copy(local.password)
            if not copy_password:
                needs_reset.append(local.username)

            if dry_run:
                created.append(f'{local.username} → {username}')
                continue

            user = User(
                username=username,
                email=local.email,
                first_name=local.first_name,
                last_name=local.last_name,
                institution=local.institution,
                date_joined=local.date_joined,
                # role / is_staff / is_superuser are intentionally omitted:
                # see PRIVILEGES ARE NEVER COPIED in the module docstring.
                # The new row keeps the model default role and no staff rights.
            )
            if copy_password:
                user.password = local.password
            else:
                user.set_unusable_password()

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
        if needs_reset:
            self.stdout.write(
                self.style.WARNING(
                    f'  {len(needs_reset)} would be created without a usable '
                    f'password (weak, unrecognised or empty source hash): '
                    f'{", ".join(sorted(needs_reset))}'
                )
            )
            self.stdout.write(
                '  note: those accounts cannot sign in until a password is '
                f'set. Have each user reset it, or set one directly in {target}.'
            )
        self.stdout.write(
            '  note: privileges (role, is_staff, is_superuser, is_active) are '
            f'never synced — grant them in {target} deliberately.'
        )

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
        """Refresh the profile fields listed in _SYNCABLE_PROFILE_FIELDS.

        Deliberately does not touch role, is_staff, is_superuser or is_active:
        those are privilege and lifecycle decisions that belong to whoever
        operates the target database, not to a developer machine.
        """
        for field in _SYNCABLE_PROFILE_FIELDS:
            setattr(target, field, getattr(source, field))

    def _unique_username(self, base: str, taken: set) -> str:
        if base not in taken:
            return base
        suffix = 1
        candidate = f'{base}_{suffix}'
        while candidate in taken:
            suffix += 1
            candidate = f'{base}_{suffix}'
        return candidate