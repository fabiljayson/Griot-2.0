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
                    'An intricately carved royal mask of the Bamoun sultanate, '
                    'adorned with beads and cowrie shells. Worn during '
                    'ceremonial dances and royal celebrations in Foumban.'
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
                    'A spectacular beaded elephant mask from the Bamileke '
                    'highlands. The elephant symbolizes strength and royalty '
                    'and features prominently in the famous Elephant Dance.'
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
                    'A bronze statue commemorating King Njoya of the Bamoun '
                    'sultanate, inventor of the Bamoun script and patron of '
                    'the arts. A symbol of African innovation and statecraft.'
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
                    'A decorated calabash vessel from the Kirdi (Montagnard) '
                    'peoples of northern Cameroon, used for storing grain and '
                    'water. The geometric burnt patterns encode clan identity.'
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
                    'A towering headdress from the Mambila people of the '
                    'Adamawa plateau, combining wood and raffia. Worn during '
                    'funerary and initiation ceremonies to honor ancestors.'
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
                    'A large slit drum associated with the Ngondo festival of '
                    'the Sawa people. Its rhythms summon the spirits of the '
                    'water and open the annual celebration on the Wouri river.'
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
