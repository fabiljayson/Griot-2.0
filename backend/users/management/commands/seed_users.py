"""
Management command to create the platform admin and demo users.

Usage:
    python manage.py seed_users
    python manage.py seed_users --password 'change-me'
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

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
        password = options['password'] or 'demo12345'
        if not options['password']:
            self.stdout.write(
                self.style.WARNING(
                    'Using the default demo password (demo12345) - pass '
                    '--password to set a secure one. Only for local dev!')
            )

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
