"""
First-pass-only XP for quizzes.

Both the web flow (``web/services.finish_quiz``) and the API
(``gamification.views.QuizAttemptViewSet.finish``) awarded the full quiz reward
on *every* passing attempt, and ``start_quiz`` opens a fresh attempt on demand.
Nothing stopped a reader re-taking a quiz repeatedly to farm XP — 5 retakes of
a 100 XP quiz paid out 500 XP, inflating leaderboard position and every
threshold-gated badge (``xp_required``, ``quizzes_passed_required``).

The rule is first-pass-only: the reward is paid once per (user, quiz). Retakes
are still allowed and still count as activity for streaks, they just do not pay
out again. The check is a database query, not a cache, because XP is a durable
ledger: a cache eviction or expiry must never be able to re-open the payout.

This bounds the *reward*, not the activity. A determined user can still open
and submit unlimited attempts (cheap rows, and each is real engagement with the
material); what they cannot do is convert that into a second payout.
"""

from gamification.models import QuizAttempt


def already_earned_quiz_xp(user, quiz, *, exclude_attempt=None) -> bool:
    """True when ``user`` has already been paid the passing reward for ``quiz``.

    ``exclude_attempt`` is the attempt currently being graded. It is normally
    still ``IN_PROGRESS`` in the database at the moment this is called, so it
    cannot match, but passing it makes the call correct and idempotent if it is
    ever used after the attempt has been saved.
    """
    earned = QuizAttempt.objects.filter(
        user=user,
        quiz=quiz,
        status=QuizAttempt.Status.COMPLETED,
        xp_earned__gt=0,
    )
    if exclude_attempt is not None and exclude_attempt.pk is not None:
        earned = earned.exclude(pk=exclude_attempt.pk)
    return earned.exists()
