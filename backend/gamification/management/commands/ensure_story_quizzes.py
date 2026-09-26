"""Backfill quizzes for published stories that are missing one.

The ``post_save`` receiver provisions a quiz the moment a story is published,
so this command exists for the stories that predate it and for repairing a
partially seeded database after a failed run. It is safe to run repeatedly.

Usage:
    python manage.py ensure_story_quizzes
    python manage.py ensure_story_quizzes --dry-run
"""

from django.core.management.base import BaseCommand

from gamification.services.quiz_provisioner import (
    ensure_quizzes_for_published_stories,
)
from stories.models import Story


class Command(BaseCommand):
    help = 'Ensure every published story has a playable quiz'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report what would change without writing.',
        )
        parser.add_argument(
            '--verbose-quiz',
            action='store_true',
            help='List each story and how many questions it gained.',
        )

    def handle(self, *args, **options):
        if options['dry_run']:
            self._report(options.get('verbose_quiz'))
            return

        summary = ensure_quizzes_for_published_stories()
        self.stdout.write(
            self.style.SUCCESS(
                f'Checked {summary["stories"]} published stories: '
                f'{summary["created"]} quizzes created, '
                f'{summary["repaired"]} repaired, '
                f'{summary["unchanged"]} already complete '
                f'({summary["questions_added"]} questions added).'
            )
        )

    def _report(self, verbose):
        queryset = Story.objects.filter(
            status=Story.Status.PUBLISHED,
        ).select_related('author').prefetch_related('categories')

        missing = 0
        for story in queryset:
            existing = story.quiz if hasattr(story, 'quiz') else None
            question_count = existing.questions.count() if existing else 0
            if question_count:
                if verbose:
                    self.stdout.write(
                        f'  ok   {story.title} ({question_count} questions)'
                    )
                continue
            missing += 1
            self.stdout.write(
                self.style.WARNING(
                    f'  MISS {story.title} — no playable quiz'
                )
            )

        self.stdout.write(
            f'{missing} published {"story needs" if missing == 1 else "stories need"} '
            'a quiz.'
        )
