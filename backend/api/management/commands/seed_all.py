"""
One-command database seeding for local development and staging.

Runs the full pipeline in dependency order:

    users → stories → gamification → qr codes

Usage:
    python manage.py seed_all
    python manage.py seed_all --clear  # Clear existing seeded data first
"""

from django.core.management import call_command
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Seed the database end-to-end (users, stories, gamification, QR artifacts)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing seeded data before re-seeding',
        )

    def handle(self, *args, **options):
        clear = options['clear']

        self.stdout.write('Seeding database...')
        call_command('seed_users')
        call_command('seed_stories', clear=clear)
        call_command('seed_gamification', clear=clear)
        call_command('seed_qr_codes', clear=clear)

        self.stdout.write(
            self.style.SUCCESS('Database seeded successfully!')
        )
