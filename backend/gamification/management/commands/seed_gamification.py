"""
Management command to seed the database with quiz and badge data.

Usage:
    python manage.py seed_gamification
    python manage.py seed_gamification --clear  # Clear existing data first
"""

from django.core.management.base import BaseCommand

from gamification.models import Badge, Quiz
from gamification.services.quiz_provisioner import (
    ensure_quizzes_for_published_stories,
)


class Command(BaseCommand):
    help = 'Seed the database with quizzes and badges for gamification'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing gamification data before seeding',
        )

    def handle(self, *args, **options):
        if options['clear']:
            self.stdout.write('Clearing existing gamification data...')
            Quiz.objects.all().delete()
            Badge.objects.all().delete()

        # Create badges
        self._create_badges()

        # Create quizzes for published stories
        self._create_quizzes()

        self.stdout.write(self.style.SUCCESS('Successfully seeded gamification data!'))

    def _create_badges(self):
        """Create achievement badges."""
        badge_data = [
            # Reading badges
            {
                'name': 'First Steps',
                'slug': 'first-steps',
                'description': 'Read your first story on African Teller',
                'emoji': '👣',
                'category': 'reading',
                'stories_read_required': 1,
                'color': '#C85A32',
            },
            {
                'name': 'Story Seeker',
                'slug': 'story-seeker',
                'description': 'Read 5 different stories',
                'emoji': '📖',
                'category': 'reading',
                'stories_read_required': 5,
                'color': '#D99B26',
            },
            {
                'name': 'Cultural Explorer',
                'slug': 'cultural-explorer',
                'description': 'Read 10 different stories',
                'emoji': '🗺️',
                'category': 'exploration',
                'stories_read_required': 10,
                'color': '#2D5A27',
            },
            {
                'name': 'Heritage Guardian',
                'slug': 'heritage-guardian',
                'description': 'Read 25 different stories',
                'emoji': '🏛️',
                'category': 'exploration',
                'stories_read_required': 25,
                'color': '#4B0082',
            },
            {
                'name': 'Wisdom Keeper',
                'slug': 'wisdom-keeper',
                'description': 'Read 50 different stories',
                'emoji': '📚',
                'category': 'reading',
                'stories_read_required': 50,
                'color': '#8B4513',
                'is_secret': True,
            },

            # Quiz badges
            {
                'name': 'Quiz Rookie',
                'slug': 'quiz-rookie',
                'description': 'Pass your first quiz',
                'emoji': '🧠',
                'category': 'quiz',
                'quizzes_passed_required': 1,
                'color': '#C85A32',
            },
            {
                'name': 'Knowledge Champion',
                'slug': 'knowledge-champion',
                'description': 'Pass 5 quizzes',
                'emoji': '🏆',
                'category': 'quiz',
                'quizzes_passed_required': 5,
                'color': '#D99B26',
            },
            {
                'name': 'Quiz Master',
                'slug': 'quiz-master',
                'description': 'Pass 10 quizzes with 100% score',
                'emoji': '🎓',
                'category': 'quiz',
                'quizzes_passed_required': 10,
                'color': '#2D5A27',
                'is_secret': True,
            },

            # XP badges
            {
                'name': 'Rising Star',
                'slug': 'rising-star',
                'description': 'Earn 100 XP',
                'emoji': '⭐',
                'category': 'reading',
                'xp_required': 100,
                'color': '#FFD700',
            },
            {
                'name': 'Heritage Hero',
                'slug': 'heritage-hero',
                'description': 'Earn 500 XP',
                'emoji': '🦸',
                'category': 'special',
                'xp_required': 500,
                'color': '#C85A32',
            },
            {
                'name': 'Legendary Explorer',
                'slug': 'legendary-explorer',
                'description': 'Earn 1000 XP',
                'emoji': '👑',
                'category': 'special',
                'xp_required': 1000,
                'color': '#DAA520',
                'is_secret': True,
            },

            # Streak badges
            {
                'name': 'Dedicated Reader',
                'slug': 'dedicated-reader',
                'description': 'Read stories 3 days in a row',
                'emoji': '🔥',
                'category': 'reading',
                'xp_required': 0,
                'color': '#FF4500',
            },
        ]

        for data in badge_data:
            badge, created = Badge.objects.get_or_create(
                slug=data['slug'],
                defaults=data,
            )
            if created:
                self.stdout.write(f'  Created badge: {data["name"]}')

    def _create_quizzes(self):
        """Create quizzes for published stories.

        Delegates to the provisioner so seeding, publishing and backfilling all
        produce identical quizzes.
        """
        summary = ensure_quizzes_for_published_stories()
        self.stdout.write(
            f'  Quizzes: {summary["stories"]} stories checked '
            f'({summary["created"]} created, {summary["repaired"]} repaired, '
            f'{summary["unchanged"]} already present)'
        )
