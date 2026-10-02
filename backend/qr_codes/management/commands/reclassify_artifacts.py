"""Re-classify existing Artifact rows.

The crawl importer used to collapse every row's taxonomy into
`Category.OTHER`, which left 127 of 134 artifacts in that bucket. Fixing the
importer only helps future imports; this command repairs what is already in
the database.

It classifies from text the row already carries — title, description,
historical significance, and the story narrative. That is a weaker signal than
a fresh crawl has (the original `material_type` from the crawler is gone), so
expect some rows to land on `other` legitimately. The command reports how many
it moved and how many stayed, so the outcome is visible rather than inferred
from a row count.

Usage:
    python manage.py reclassify_artifacts --dry-run
    python manage.py reclassify_artifacts --limit 100
    python manage.py reclassify_artifacts --dry-run
"""

from django.core.management.base import BaseCommand
from django.db import transaction

from qr_codes.classification import (
    classify_content_type,
    classify_material,
    classification_text,
)
from qr_codes.models import Artifact

# Classifying a national park as a "sculpture" or a calabash vessel as a
# "tool" is worse than leaving the row alone, so the backfill demands real
# evidence. Two keyword hits is a low bar that a single incidental word in a
# long narrative cannot clear, and a single hit from stored prose is not
# enough to overwrite a curated value.
MIN_SCORE = 2


def classify_artifact(artifact: Artifact) -> tuple[str, str]:
    """Return (content_type, category) for one artifact, from its own text.

    Deliberately does NOT read `artifact.story`. The story field is the long
    historical narrative, and it mentions every kind of object mentioned in
    the surrounding history — a park's story talks about the statues in it, a
    vessel's story about the beads woven into it. Classifying over it
    reliably picks the wrong object. Title, description and historical
    significance describe the row itself.
    """
    text = classification_text(
        artifact.title,
        artifact.description,
        artifact.historical_significance,
    )
    return (
        classify_content_type(text, min_score=MIN_SCORE),
        classify_material(text, min_score=MIN_SCORE),
    )


class Command(BaseCommand):
    help = 'Re-run content-type and material classification over existing artifacts'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report what would change without writing to the database',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=0,
            help='Stop after N rows (0 means no limit). Useful for spot checks.',
        )
        parser.add_argument(
            '--force',
            action='store_true',
            help=(
                'Also re-classify rows that already have a real category. Off by '
                'default: an existing non-"other" category is curated data, and '
                'this command classifies from prose that cannot match a human.'
            ),
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        limit = options['limit']
        force = options['force']

        # Default to the rows the broken importer created. Re-classifying rows
        # that already carry a curated category was measured corrupting them:
        # "Bamoun Royal Mask" (category=mask) became "jewelry" because its
        # description mentions beads more often than it says "mask".
        queryset = Artifact.objects.all().order_by('id')
        if not force:
            queryset = queryset.filter(category=Artifact.Category.OTHER)
        if limit:
            queryset = queryset[:limit]

        total = queryset.count() if not limit else min(limit, Artifact.objects.count())

        changed_category = 0
        changed_content_type = 0
        unchanged = 0
        still_other = 0

        self.stdout.write(
            self.style.NOTICE(
                f'\n🔍 Inspecting {total} artifacts'
                f'{" (dry run)" if dry_run else ""}\n'
            )
        )

        with transaction.atomic():
            for artifact in queryset:
                content_type, category = classify_artifact(artifact)

                if category == Artifact.Category.OTHER:
                    still_other += 1

                changed = False
                if artifact.category != category:
                    if dry_run:
                        self.stdout.write(
                            f'  {artifact.slug}: {artifact.category} → {category}'
                        )
                    else:
                        artifact.category = category
                        changed = True
                    changed_category += 1

                if artifact.content_type != content_type:
                    if dry_run:
                        self.stdout.write(
                            f'  {artifact.slug}: content_type '
                            f'{artifact.content_type} → {content_type}'
                        )
                    else:
                        artifact.content_type = content_type
                        changed = True
                    changed_content_type += 1

                if changed and not dry_run:
                    artifact.save(update_fields=['category', 'content_type'])
                else:
                    unchanged += 1

            if dry_run:
                transaction.set_rollback(True)

        self.stdout.write(f'\n{"=" * 60}')
        self.stdout.write(f'  Rows examined:            {total}')
        self.stdout.write(f'  Content type set:        {changed_content_type}')
        self.stdout.write(f'  Category changed:        {changed_category}')
        self.stdout.write(f'  Still "other":           {still_other}')
        self.stdout.write(f'  Unchanged:               {unchanged}')
        self.stdout.write(
            self.style.WARNING(
                f'\n  ⚠️  {still_other} of these rows have no material type and are\n'
                '      not artifacts at all — travel-guide entries, region guides and\n'
                '      practical notes ("visa", "currency", "the equatorial zone")\n'
                '      stored in a table meant for museum objects. Their "other"\n'
                '      category is correct; the question is whether they belong here.\n'
                '      See docs/ROADMAP.md Phase 1.'
            )
        )
        if not force:
            self.stdout.write(
                self.style.NOTICE(
                    f'  {Artifact.objects.exclude(category=Artifact.Category.OTHER).count()} '
                    'curated rows left untouched (pass --force to re-classify them).'
                )
            )
        self.stdout.write(f'{"=" * 60}\n')