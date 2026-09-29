"""
Management command to create the platform admin and demo users.

Usage:
    python manage.py seed_users
    python manage.py seed_users --password 'change-me'

The fallback password is published in this repository, so the command refuses
to run anywhere except a developer machine unless an explicit password is
supplied. See config.safety for the exact rule.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from config.safety import (
    INSECURE_DEFAULT_PASSWORD,
    assert_safe_environment,
    is_production,
    require_explicit_password,
)

User = get_user_model()


class Command(BaseCommand):
    help = 'Create the platform admin and demo users for every role'

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default=None,
            help='Password assigned to created users (default: demo12345)',
        )

    def handle(self, *args, **options):
        assert_safe_environment(
            'seed_users',
            reason=(
                'it creates an is_superuser admin account with a password '
                'that is public in this repository.'
            ),
        )

        password = options['password']
        if not password:
            if is_production():
                # `assert_safe_environment` already let us through, so this
                # is the deliberate override path. The demo password is still
                # refused: opting in to the command is not opting in to a
                # published credential.
                password = require_explicit_password('seed_users', password)
                self.stdout.write(
                    self.style.WARNING(
                        'Seeding a hosted database. Rotate every seeded '
                        'password before traffic reaches it.'
                    )
                )
            else:
                password = INSECURE_DEFAULT_PASSWORD
                self.stdout.write(
                    self.style.WARNING(
                        f'Using the default demo password ({INSECURE_DEFAULT_PASSWORD}) '
                        f'- pass --password to set a secure one. Only for local dev!'
                    )
                )
        elif password == INSECURE_DEFAULT_PASSWORD and is_production():
            require_explicit_password('seed_users', password)

        users = {
            'admin': {
                'email': 'admin@africanteller.com',
                'role': 'admin',
                'is_staff': True,
                'is_superuser': True,
            },
            'demo_visitor': {
                'email': 'visitor@africanteller.com',
                'role': 'visitor',
            },
            'demo_contributor': {
                'email': 'contributor@africanteller.com',
                'role': 'contributor',
            },
            'demo_manager': {
                'email': 'manager@africanteller.com',
                'role': 'institution_manager',
                'institution': 'National Museum of Cameroon',
            },
        }

        for username, fields in users.items():
            user, created = User.objects.get_or_create(
                username=username,
                defaults=fields,
            )
            if created or not user.has_usable_password():
                user.set_password(password)
                user.save(update_fields=['password'])
            self.stdout.write(f'  {"Created" if created else "Verified"} user: {username}')

        self.stdout.write(
            self.style.SUCCESS(f'Successfully seeded {len(users)} users!')
        )
