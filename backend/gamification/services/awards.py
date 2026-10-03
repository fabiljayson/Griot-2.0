"""Badge and certificate awards — the single implementation.

Constitution I requires gamification to be "implemented once in models/services
and reused — never duplicated per surface". It was not. The sweep existed twice,
in ``gamification.views.QuizAttemptViewSet._check_badges`` and in
``web.services.finish_quiz``, and the two copies had already drifted: the API
swept only on a first pass, the web on every pass. Both sat inside
``if attempt.passed``, and no quiz attempt in the database had ever passed — so
the whole feature had produced zero rows while 503 profiles already cleared the
easiest threshold.

Every path that moves a counter a badge reads calls
:func:`award_eligible_badges`:

* ``gamification.views`` finish — quiz XP, ``quizzes_passed``, streak
* ``web.services.finish_quiz`` — the same, through the web surface
* ``web.services.record_progress`` — ``stories_read`` and streak

Call it after the counters have been written, not before.
"""

import logging

from django.db import transaction

from ..models import Badge, Certificate, UserBadge, UserProfile

logger = logging.getLogger(__name__)

#: Badge categories that issue a certificate, and which type they issue.
#:
#: Reading and quiz only. `Certificate.Type` also offers ``EXPLORER`` and
#: ``CONTRIBUTOR``; wiring those is a product decision this phase did not take,
#: so exploration badges (Cultural Explorer, Heritage Guardian) deliberately
#: earn the badge and nothing more.
CERTIFICATE_TYPES = {
    Badge.Category.READING: Certificate.Type.READING,
    Badge.Category.QUIZ: Certificate.Type.QUIZ,
}


def badge_is_earned(badge, profile):
    """Whether ``profile`` satisfies ``badge``.

    A requirement of *0* means "not required" on that dimension, so a badge
    asking only for stories correctly ignores XP. Satisfaction is therefore
    **any** of the configured requirements being met — the semantics both
    original copies used, kept deliberately: every seeded badge sets exactly one
    requirement, and changing to AND would alter behaviour nobody asked to
    change.

    A badge with *no* configured requirement is skipped and warned about rather
    than awarded to everyone. It cannot be earned — which is exactly the defect
    `Badge.clean()` now refuses at creation — and silently awarding it would be
    the same class of quiet wrongness this module exists to end.

    Streaks read ``max(current, longest)``: the badge says "read stories 3 days
    in a row", so a reader who once did keeps it after the run breaks, and a
    run counted at the time is not un-earned later.
    """
    configured = [
        (badge.xp_required, profile.total_xp),
        (badge.stories_read_required, profile.stories_read),
        (badge.quizzes_passed_required, profile.quizzes_passed),
        (badge.streak_required, max(profile.current_streak, profile.longest_streak)),
    ]
    configured = [(need, have) for need, have in configured if need]
    if not configured:
        logger.warning(
            'badge "%s" (%s) has no requirement set and can never be awarded',
            badge.slug, badge.name,
        )
        return False
    return any(have >= need for need, have in configured)


def _issue_certificate(badge, user, profile):
    """Create the certificate for ``badge`` if its category maps to one.

    Returns the certificate, or ``None`` when the category has no mapping or the
    reader already holds this one. Keyed on ``(user, type, title)`` so a replay
    cannot mint a second copy of the same award.
    """
    cert_type = CERTIFICATE_TYPES.get(badge.category)
    if cert_type is None:
        return None
    _, created = Certificate.objects.get_or_create(
        user=user,
        certificate_type=cert_type,
        title=badge.name,
        defaults={
            'description': badge.description,
            'stories_read': profile.stories_read,
            'quizzes_passed': profile.quizzes_passed,
            'level_achieved': profile.level,
        },
    )
    return created


@transaction.atomic
def award_eligible_badges(user):
    """Award every badge ``user`` has just become eligible for.

    Returns the list of badges newly awarded — empty on a call where nothing
    changed, which is the common case and is fine. Safe to call as often as you
    like: badges already held are excluded up front, and creation goes through
    ``get_or_create`` against the ``(user, badge)`` unique constraint, so a
    replay, a second surface, or two requests racing cannot double-award.
    """
    profile, _ = UserProfile.objects.get_or_create(user=user)
    earned_ids = set(
        UserBadge.objects.filter(user=user).values_list('badge_id', flat=True)
    )

    awarded = []
    for badge in Badge.objects.filter(is_active=True).exclude(id__in=earned_ids):
        if not badge_is_earned(badge, profile):
            continue
        _, created = UserBadge.objects.get_or_create(user=user, badge=badge)
        if not created:
            continue
        _issue_certificate(badge, user, profile)
        awarded.append(badge)

    if awarded:
        logger.info(
            'awarded %d badge(s) to user %s: %s',
            len(awarded), user.pk, ', '.join(b.slug for b in awarded),
        )
    return awarded
