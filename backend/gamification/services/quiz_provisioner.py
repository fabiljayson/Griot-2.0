"""Guarantee that every published story has a playable quiz.

The story reader's "Take Quiz" CTA resolves a quiz by story id, so a published
story without a quiz shows "Quiz coming soon". This module is the single place
that closes that gap: :func:`ensure_quiz_for_story` is called from the
``post_save`` receiver whenever a story becomes published, from the
``seed_gamification`` command, and from ``ensure_story_quizzes`` for backfills.

It is idempotent — re-running it never duplicates questions or discards an
editor's corrections, it only fills in what is missing.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.db import transaction

from gamification.models import Quiz, QuizQuestion
from gamification.services.quiz_content import quiz_data_for


@dataclass(frozen=True)
class ProvisionResult:
    """Outcome of provisioning one story's quiz."""

    quiz: Quiz
    created: bool
    questions_added: int

    @property
    def changed(self) -> bool:
        return self.created or self.questions_added > 0


def _published_peers(exclude=None):
    """Published stories used to build plausible distractor options."""
    from stories.models import Story

    queryset = Story.objects.filter(status=Story.Status.PUBLISHED).only(
        'id', 'title', 'region', 'summary',
    )
    if exclude is not None and exclude.pk:
        queryset = queryset.exclude(pk=exclude.pk)
    return list(queryset)


@transaction.atomic
def ensure_quiz_for_story(story, *, repair=True) -> ProvisionResult:
    """Return the quiz for ``story``, creating questions when it has none.

    ``repair`` also backfills a quiz that exists but has no questions, which is
    the state a story lands in if a previous seed run was interrupted.

    ``questions_added`` is the number of questions written by this call, so
    ``0`` means the story was already fully provisioned and nothing was
    touched.
    """
    quiz, created = Quiz.objects.get_or_create(
        story=story,
        defaults={
            'title': f'Test Your Knowledge: {story.title}',
            'description': f'Check what you remember from "{story.title}".',
            'passing_score': 70,
        },
    )

    if quiz.questions.exists() or (not created and not repair):
        return ProvisionResult(quiz=quiz, created=created, questions_added=0)

    data = quiz_data_for(story, peers=_published_peers(exclude=story))

    # Keep the curated title/description in step with the content.
    changed = []
    if quiz.title != data['title']:
        quiz.title = data['title']
        changed.append('title')
    if quiz.description != data['description']:
        quiz.description = data['description']
        changed.append('description')
    if changed:
        quiz.save(update_fields=changed)

    questions = data['questions']
    for index, question in enumerate(questions, start=1):
        QuizQuestion.objects.create(quiz=quiz, order=index, **question)

    return ProvisionResult(
        quiz=quiz,
        created=created,
        questions_added=len(questions),
    )


def ensure_quizzes_for_published_stories(queryset=None) -> dict:
    """Provision quizzes for every published story and return a summary dict."""
    from stories.models import Story

    if queryset is None:
        queryset = Story.objects.filter(status=Story.Status.PUBLISHED)

    summary = {
        'stories': 0,
        'created': 0,
        'repaired': 0,
        'questions_added': 0,
        'unchanged': 0,
    }
    stories = queryset.select_related('author').prefetch_related('categories')
    for story in stories:
        summary['stories'] += 1
        result = ensure_quiz_for_story(story)
        summary['questions_added'] += result.questions_added
        if result.created:
            summary['created'] += 1
        elif result.questions_added:
            summary['repaired'] += 1
        else:
            summary['unchanged'] += 1
    return summary
