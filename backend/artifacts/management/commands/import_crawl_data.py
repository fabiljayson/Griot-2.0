"""
Management command to import crawled Cameroon content data into Artifact model.

Reads cameroon_content.json and creates Artifact instances with:
- Combined story (description + historical_significance)
- Category and location metadata
- Downloads associated images to media/artifacts/images/

Usage:
    python manage.py import_crawl_data
    python manage.py import_crawl_data --dry-run
    python manage.py import_crawl_data --json-path /path/to/file.json
"""

import json
import os
import shutil
import time
from pathlib import Path
from urllib.parse import urlparse

import requests
from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils.text import slugify

from qr_codes.models import Artifact


class Command(BaseCommand):
    help = 'Import crawled content data from JSON file into Artifact model'

    def add_arguments(self, parser):
        parser.add_argument(
            '--json-path',
            type=str,
            default=str(Path(__file__).resolve().parent.parent.parent.parent.parent / 'downloads' / 'cameroon_content.json'),
            help='Path to the crawled JSON file',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Parse and validate data without saving to database',
        )
        parser.add_argument(
            '--skip-images',
            action='store_true',
            help='Skip downloading images from source URLs',
        )
        parser.add_argument(
            '--update-existing',
            action='store_true',
            help='Update existing artifacts if slug matches',
        )

    def handle(self, *args, **options):
        json_path = options['json_path']
        dry_run = options['dry_run']
        skip_images = options['skip_images']
        update_existing = options['update_existing']

        self.stdout.write(self.style.NOTICE(f'\n📂 Reading data from: {json_path}\n'))

        # Load JSON data
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                crawl_data = json.load(f)
        except FileNotFoundError:
            self.stdout.write(self.style.ERROR(f'❌ File not found: {json_path}'))
            return
        except json.JSONDecodeError as e:
            self.stdout.write(self.style.ERROR(f'❌ Invalid JSON: {e}'))
            return

        self.stdout.write(self.style.NOTICE(f'📄 Found {len(crawl_data)} items to process\n'))

        # Ensure media directories exist
        media_root = Path(settings.MEDIA_ROOT)
        artifacts_dir = media_root / 'artifacts'
        images_dir = artifacts_dir / 'images'
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        images_dir.mkdir(parents=True, exist_ok=True)

        created_count = 0
        updated_count = 0
        skipped_count = 0
        image_count = 0

        for i, item in enumerate(crawl_data, 1):
            slug = item.get('id', '')
            title = item.get('title', '')
            category = item.get('category', 'culture').lower()
            location = item.get('location', '')
            description = item.get('description', '')
            historical_significance = item.get('historical_significance', '')
            source_url = item.get('source_url', '')
            images = item.get('images', [])

            # Build the story field by combining description + historical context
            story_parts = []
            if description:
                story_parts.append(description)
            if historical_significance and historical_significance != description:
                story_parts.append(f'\n\n**Historical Significance:**\n\n{historical_significance}')
            story = '\n'.join(story_parts).strip()

            if not story:
                self.stdout.write(self.style.WARNING(f'  ⚠️  [{i}] Skipping "{title}" — no story content'))
                skipped_count += 1
                continue

            # Map old category values to the new qr_codes.Artifact categories
            category_map = {
                'kingdom': 'other',
                'landmark': 'other',
                'artifact': 'other',
                'legend': 'other',
                'culture': 'other',
            }
            category = category_map.get(category, 'other')

            # Check for existing artifact
            existing = Artifact.objects.filter(slug=slug).first()

            if existing:
                if update_existing:
                    if dry_run:
                        self.stdout.write(f'  🔄 [{i}] Would update: {title}')
                        updated_count += 1
                    else:
                        existing.title = title[:200]
                        existing.category = category
                        existing.region = location[:100]
                        existing.story = story
                        existing.historical_significance = historical_significance
                        existing.source_url = source_url
                        existing.save()
                        if not skip_images and images:
                            image_count += self._attach_images(existing, images, images_dir)
                        self.stdout.write(self.style.SUCCESS(f'  🔄 [{i}] Updated: {title}'))
                        updated_count += 1
                else:
                    self.stdout.write(f'  ⏭️  [{i}] Skipping duplicate: {title}')
                    skipped_count += 1
                continue

            if dry_run:
                self.stdout.write(f'  ✅ [{i}] Would create: {title} ({category}) — {len(story)} chars')
                created_count += 1
                continue

            # Create the artifact (QR code auto-generates on save)
            artifact = Artifact(
                title=title[:200],
                slug=slug,
                category=category,
                region=location[:100],
                story=story,
                historical_significance=historical_significance,
                source_url=source_url,
                is_published=True,
            )
            artifact.save()
            self.stdout.write(self.style.SUCCESS(f'  ✅ [{i}] Created: {title} ({category})'))
            created_count += 1

            # Download images
            if not skip_images and images:
                image_count += self._attach_images(artifact, images, images_dir)

            # Small delay to avoid overwhelming the server
            if i % 10 == 0:
                time.sleep(0.5)

        # Summary
        self.stdout.write(f'\n{"="*60}')
        self.stdout.write(self.style.SUCCESS(f'✅ IMPORT COMPLETE'))
        self.stdout.write(f'{"="*60}')
        self.stdout.write(f'  Created:  {created_count}')
        self.stdout.write(f'  Updated:  {updated_count}')
        self.stdout.write(f'  Skipped:  {skipped_count}')
        self.stdout.write(f'  Images:   {image_count}')
        self.stdout.write(f'  Total:    {Artifact.objects.count()} artifacts in database')
        self.stdout.write(f'{"="*60}\n')

    def _download_image(self, url, slug, images_dir):
        """Download an image from URL and save to media directory."""
        try:
            response = requests.get(url, timeout=15, stream=True)
            response.raise_for_status()

            # Determine file extension
            path = urlparse(url).path.lower()
            ext = '.jpg'  # default
            for e in ('.png', '.gif', '.webp', '.bmp'):
                if e in path:
                    ext = e
                    break

            # Generate filename
            filename = f'{slug}{ext}'
            filepath = images_dir / filename

            # Save the file
            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(8192):
                    f.write(chunk)

            return True

        except Exception as e:
            self.stdout.write(self.style.WARNING(f'    ⚠️  Failed to download {url}: {e}'))
            return False

    def _attach_images(self, artifact, images, images_dir):
        """Attach crawled local images to the primary and gallery fields."""
        project_root = Path(settings.BASE_DIR).parent
        attached = []

        for index, image_data in enumerate(images[:3]):
            local_filename = image_data.get('local_filename', '')
            source = project_root / 'downloads' / local_filename
            if not source.exists():
                continue

            filename = f'{artifact.slug}-{index + 1}{source.suffix.lower()}'
            destination = images_dir / filename
            shutil.copy2(source, destination)
            relative_path = f'artifacts/images/{filename}'
            attached.append(f'{settings.MEDIA_URL}{relative_path}')
            if index == 0:
                artifact.image = relative_path

        if attached:
            artifact.additional_images = attached[1:]
            artifact.save(update_fields=['image', 'additional_images'])
        return len(attached)
