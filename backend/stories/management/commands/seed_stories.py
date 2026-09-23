"""
Management command to seed the database with cultural stories and categories.

Usage:
    python manage.py seed_stories
    python manage.py seed_stories --clear  # Clear existing data first
"""

from pathlib import Path
import shutil

from django.conf import settings
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.utils.text import slugify

from stories.models import Story, StoryCategory
from stories.seed_data import CATEGORY_DATA, STORIES

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed the database with cultural stories and categories from Cameroon'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing stories and categories before seeding',
        )

    def handle(self, *args, **options):
        if options['clear']:
            self.stdout.write('Clearing existing stories and categories...')
            Story.objects.all().delete()
            StoryCategory.objects.all().delete()

        # Create or get the admin user for seeding
        admin_user, _ = User.objects.get_or_create(
            username='admin',
            defaults={
                'email': 'admin@africanteller.com',
                'role': 'admin',
                'is_staff': True,
                'is_superuser': True,
            }
        )
        if not admin_user.has_usable_password():
            admin_user.set_password('admin123')
            admin_user.save()

        # Create categories
        categories = self._create_categories()
        
        # Create stories
        self._create_stories(admin_user, categories)
        
        self.stdout.write(self.style.SUCCESS('Successfully seeded database with cultural stories!'))

    def _create_categories(self):
        """Create story categories based on crawled content."""
        
        categories = {}
        for data in CATEGORY_DATA:
            category, created = StoryCategory.objects.get_or_create(
                name=data['name'],
                defaults=data
            )
            categories[data['name']] = category
            if created:
                self.stdout.write(f'  Created category: {data["name"]}')
        
        return categories

    def _create_stories(self, author, categories):
        """Create stories based on crawled content from discover-cameroon.com."""
        
        for story_data in STORIES:
            # Get categories
            category_names = story_data.pop('categories')
            category_objects = []
            for name in category_names:
                if name in categories:
                    category_objects.append(categories[name])
            
            # Create story
            story, created = Story.objects.get_or_create(
                title=story_data['title'],
                defaults={
                    **story_data,
                    'author': author,
                    'status': 'published',
                }
            )
            
            if created:
                # Set categories
                story.categories.set(category_objects)
                self.stdout.write(f'  Created story: {story_data["title"]}')
            else:
                self.stdout.write(f'  Story already exists: {story_data["title"]}')

            if self._attach_cover_image(story):
                self.stdout.write(f'  Attached cover image: {story.title}')
        
        self.stdout.write(f'\nCreated {len(STORIES)} stories across {len(categories)} categories')

    def _attach_cover_image(self, story):
        """Copy a matching crawled image into MEDIA_ROOT and attach it."""
        if story.cover_image:
            return False

        project_root = Path(settings.BASE_DIR).parent
        image_root = project_root / 'downloads' / 'images'
        story_slug = slugify(story.title)
        candidates = list(image_root.rglob(f'{story_slug}-01.*'))
        aliases = {
            'the-legend-of-mount-mbapits-crater-lake': 'mount-and-lake-mbapit',
            'the-baaka-pygmies-keepers-of-the-forest': 'visit-pygmies-encampments',
            'the-bamileke-guardians-of-the-highlands': 'cameroon-cultures',
            'the-bamoun-sultanate-a-legacy-of-innovation': 'foumban',
            'bimbia-where-memory-lives': 'bimbia',
            'the-mysterious-lakes-of-manengouba': 'manengouba-mountains',
            'the-ekom-nkam-waterfalls-where-tarzan-was-born': 'ekom-nkam-waterfalls',
            'the-bamileke-elephant-dance': 'elephant',
            'the-sacred-forest-of-foreke-dschang': 'dschang-attractions',
        }
        if not candidates and story_slug in aliases:
            candidates = sorted(image_root.rglob(f"{aliases[story_slug]}-01.*"))
        if not candidates:
            return False

        destination = Path(settings.MEDIA_ROOT) / 'stories' / 'covers'
        destination.mkdir(parents=True, exist_ok=True)
        filename = f'{story_slug}{candidates[0].suffix.lower()}'
        shutil.copy2(candidates[0], destination / filename)
        story.cover_image = f'stories/covers/{filename}'
        story.save(update_fields=['cover_image'])
        return True
