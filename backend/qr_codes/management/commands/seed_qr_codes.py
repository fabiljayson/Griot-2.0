"""
Management command to seed the database with museum artifacts for the
QR code engine.

Usage:
    python manage.py seed_qr_codes
    python manage.py seed_qr_codes --clear  # Clear existing artifacts first
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from qr_codes.models import Artifact
from stories.models import Story

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed the database with museum artifacts from Cameroon'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing artifacts before seeding',
        )

    def handle(self, *args, **options):
        artifacts = self._artifact_data()

        if options['clear']:
            # Only remove records this command owns (seeded titles), so
            # user-created artifacts are never wiped by a seed reset.
            titles = [data['title'] for data in artifacts]
            deleted, _ = Artifact.objects.filter(title__in=titles).delete()
            self.stdout.write(
                self.style.WARNING(f'Cleared {deleted} previously seeded artifacts')
            )

        admin_user = User.objects.filter(role='admin').first() or \
            User.objects.filter(is_superuser=True).first()

        published_stories = list(
            Story.objects.filter(status=Story.Status.PUBLISHED)[:3]
        )

        for data in artifacts:
            artifact, created = Artifact.objects.get_or_create(
                title=data['title'],
                defaults={
                    **data,
                    'created_by': admin_user,
                    'is_published': True,
                },
            )
            if created:
                if published_stories:
                    artifact.stories.set(published_stories)
                self.stdout.write(f'  Created artifact: {data["title"]}')
            elif artifact.description != data['description']:
                artifact.description = data['description']
                artifact.save(update_fields=['description'])
                self.stdout.write(f'  Updated artifact description: {data["title"]}')
            else:
                self.stdout.write(f'  Artifact already exists: {data["title"]}')

        self.stdout.write(
            self.style.SUCCESS(
                f'Successfully seeded {len(artifacts)} museum artifacts!'
            )
        )

    def _artifact_data(self):
        return [
            {
                'title': 'Bamoun Royal Mask',
                'description': (
                    'A carved Bamoun royal mask decorated with beads and cowrie '
                    'shells, worn in Foumban ceremonies.'
                ),
                'category': 'mask',
                'culture': 'Bamoun',
                'region': 'West Region',
                'estimated_date': '19th century',
                'materials': 'Wood, glass beads, cowrie shells',
                'museum_name': 'Foumban Royal Palace Museum',
                'floor': '1',
                'display_case': 'A-03',
            },
            {
                'title': 'Bamileke Elephant Mask',
                'description': (
                    'A beaded elephant mask from the Bamileke highlands, worn '
                    'during the Elephant Dance.'
                ),
                'category': 'mask',
                'culture': 'Bamileke',
                'region': 'West Region',
                'estimated_date': 'Early 20th century',
                'materials': 'Beaded textile, wood, raffia',
                'museum_name': 'National Museum of Yaoundé',
                'floor': '2',
                'display_case': 'M-11',
            },
            {
                'title': 'Bronze Statue of King Njoya',
                'description': (
                    'A bronze statue honoring King Njoya, Bamoun ruler, script '
                    'inventor, and patron of the arts.'
                ),
                'category': 'sculpture',
                'culture': 'Bamoun',
                'region': 'West Region',
                'estimated_date': '1920s',
                'materials': 'Bronze',
                'museum_name': 'Foumban Royal Palace Museum',
                'floor': '1',
                'display_case': 'K-07',
            },
            {
                'title': 'Kirdi Calabash Vessel',
                'description': (
                    'A decorated calabash vessel from northern Cameroon, used '
                    'to store grain and water.'
                ),
                'category': 'pottery',
                'culture': 'Kirdi (Montagnards)',
                'region': 'North Region',
                'estimated_date': '20th century',
                'materials': 'Calabash, burnt decoration',
                'museum_name': 'National Museum of Yaoundé',
                'floor': '3',
                'display_case': 'P-05',
            },
            {
                'title': 'Mambila Headdress',
                'description': (
                    'A wood-and-raffia Mambila headdress worn during funerary '
                    'and initiation ceremonies.'
                ),
                'category': 'mask',
                'culture': 'Mambila',
                'region': 'Adamawa Region',
                'estimated_date': 'Mid 20th century',
                'materials': 'Wood, raffia, plant fibers',
                'museum_name': 'Douala Museum of Art',
                'floor': '1',
                'display_case': 'H-02',
            },
            {
                'title': 'Ngondo Drum',
                'description': (
                    'A hardwood slit drum used by the Sawa people to open the '
                    'annual Ngondo festival.'
                ),
                'category': 'instrument',
                'culture': 'Douala (Sawa)',
                'region': 'Littoral Region',
                'estimated_date': '20th century',
                'materials': 'Hardwood, hide',
                'museum_name': 'Douala Museum of Art',
                'floor': '2',
                'display_case': 'D-08',
            },
        ]
