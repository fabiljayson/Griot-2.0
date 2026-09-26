"""Reading-streak accounting.

A streak is a run of consecutive *days on which the reader did anything at all*:
opened the app, read part of a story, or finished a quiz. The original
implementation only advanced on finishing a story and used ``timezone.now().date()``,
which is UTC — a reader in Cameroon (UTC+1) reading at 23:30 was credited to the
previous day and could lose a streak they had actually kept.
"""

from datetime import date, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.db import transaction
from django.utils import timezone

from ..models import UserProfile

#: Fallback when a client sends a zone the host does not know, or none at all.
#: The product is Cameroon-first, so WAT is a better guess than UTC.
DEFAULT_TIMEZONE = 'Africa/Douala'


def resolve_timezone(name):
    """Return a valid [ZoneInfo], falling back to [DEFAULT_TIMEZONE].

    The field is user-editable and arrives over the API, so an unknown zone must
    degrade to a usable one instead of raising on a request path. Use this when
    you need a zone to *compute* with; use [coerce_timezone] when you need to
    know whether the client actually named a real zone.
    """
    if not name:
        return ZoneInfo(DEFAULT_TIMEZONE)
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, KeyError):
        return ZoneInfo(DEFAULT_TIMEZONE)


def coerce_timezone(name):
    """Return the client's [ZoneInfo], or None when the name is not a real zone.

    Distinguishing "the reader asked for Europe/London" from "the client sent
    something we could not parse" matters when persisting. Flutter's
    `DateTime.timeZoneName` yields abbreviations such as ``WAT``, not IANA names,
    so an unguarded assignment would overwrite a correct stored zone with the
    default on every single launch. Returning None lets the caller keep what it
    already had while still running the streak on a usable calendar.
    """
    if not name:
        return None
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, KeyError):
        return None


def local_date(profile, when=None):
    """The reader's calendar date at [when], in the reader's own timezone."""
    when = when or timezone.now()
    return when.astimezone(resolve_timezone(profile.timezone)).date()


def live_streak(profile, today=None):
    """The streak the reader can still see on their profile right now.

    ``UserProfile.current_streak`` is the run as of the last day they were
    active, which stops being true once a day is missed. Reporting that stored
    number keeps showing "3 day streak" to someone who last read three weeks
    ago, so the value is only presented while the run is unbroken.

    Returns 0 for a missed day: the run is gone, and the reader's next activity
    starts a new one. A day that has not ended yet does not break the run.
    """
    if not profile.last_active_date:
        return 0
    today = today or local_date(profile)
    gap = today - profile.last_active_date
    # Yesterday still counts: today is not over, so the reader can still extend
    # the run. Two days ago means the run is gone.
    if gap <= timedelta(days=1):
        return profile.current_streak
    return 0


def is_active_today(profile, today=None):
    """Whether the reader has already been active on their current local day."""
    if not profile.last_active_date:
        return False
    return profile.last_active_date == (today or local_date(profile))


def streak_at_risk(profile, today=None):
    """Whether today's activity is still outstanding on a live streak.

    Drives the "keep your streak alive" prompt: true only when a streak is worth
    something today and the reader has not extended it yet.
    """
    return live_streak(profile, today) > 0 and not is_active_today(profile, today)


@transaction.atomic
def record_activity(user, timezone_name=None):
    """Count today as an active day for [user] and return their profile.

    Idempotent within a day: a second call on the same local date returns the
    unchanged profile rather than double-counting. The row is locked so two
    concurrent requests (a progress ping and a quiz finish, say) cannot each
    read the same ``current_streak`` and both write ``+1``.
    """
    profile, _ = UserProfile.objects.select_for_update().get_or_create(user=user)

    # Only overwrite the stored zone when the client named a real one. An
    # unparsable value still yields a usable calendar below via the default, but
    # must not be written back over a zone the reader already had.
    client_zone = coerce_timezone(timezone_name)
    if client_zone is not None:
        profile.timezone = client_zone.key

    today = local_date(profile)
    last_active = profile.last_active_date

    if last_active == today:
        # Already counted today, so the streak is untouched — but a corrected
        # timezone is still worth persisting.
        if client_zone is not None:
            profile.save(update_fields=['timezone', 'updated_at'])
        return profile

    if last_active == today - timedelta(days=1):
        profile.current_streak += 1
    else:
        # First day, or the previous run was missed. Either way this is day one.
        profile.current_streak = 1

    profile.longest_streak = max(profile.longest_streak, profile.current_streak)
    profile.last_active_date = today
    profile.save(update_fields=[
        'current_streak',
        'longest_streak',
        'last_active_date',
        'timezone',
        'updated_at',
    ])
    return profile


@transaction.atomic
def grant_xp_and_stats(user, xp=0, quizzes_passed=0):
    """Add XP and quiz counters, then count the day as active.

    Completing a quiz is activity, so it extends the streak whether or not the
    attempt passed — a reader who tries and fails still showed up.
    """
    profile = record_activity(user)

    if xp or quizzes_passed:
        profile.total_xp += xp
        profile.quizzes_passed += quizzes_passed
        profile.total_quiz_xp += xp
        while profile.total_xp >= profile.level * 100:
            profile.level += 1
        profile.save(update_fields=[
            'total_xp', 'quizzes_passed', 'total_quiz_xp', 'level', 'updated_at',
        ])
    return profile


def users_at_risk_today(when=None):
    """Readers with a live streak who have not been active yet today.

    Evaluated in Python rather than SQL because "today" is per-reader-local; a
    single ``last_active_date = today`` cannot express that. The queryset is
    narrowed in SQL first so only plausible rows are hydrated.

    [when] exists so the caller — and a test — can evaluate this against a
    chosen instant instead of whatever the host clock says.
    """
    candidates = (
        UserProfile.objects
        .filter(current_streak__gt=0, last_active_date__isnull=False)
        .select_related('user')
        .only(
            'id', 'user_id', 'timezone', 'current_streak', 'longest_streak',
            'last_active_date',
        )
    )
    at_risk = []
    now = when or timezone.now()
    for profile in candidates.iterator():
        if streak_at_risk(profile, local_date(profile, now)):
            at_risk.append(profile)
    return at_risk
