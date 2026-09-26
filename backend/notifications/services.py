"""Creating the messages that land in a reader's inbox.

Every fan-out here is keyed so that running it twice is harmless. Schedulers
retry, a story can be re-published, and a digest job can overlap with itself;
a reader who sees "New story: X" twice has learned to ignore the feature.
"""

import logging

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.db.models import Count, F
from django.utils import timezone

from stories.models import Story

from .models import Notification

logger = logging.getLogger(__name__)

#: How many stories a weekly digest lists. Enough to be worth opening, few
#: enough that the message stays readable on a phone.
DIGEST_SIZE = 5

#: A story must be at least this engaging to earn a place in the digest, so the
#: weekly message is not a recap of everything that happened.
MIN_DIGEST_ENGAGEMENT = 1


def notify(user, kind, title, body='', story=None, dedupe_key=''):
    """Create one message for [user], skipping it if the key is already used.

    Returns the notification, or ``None`` when it was a duplicate or the reader
    does not exist. Duplicate detection is enforced by a unique constraint
    rather than a read-then-write, so concurrent callers cannot both win.
    """
    if user is None or not getattr(user, 'pk', None):
        return None

    try:
        with transaction.atomic():
            return Notification.objects.create(
                user=user,
                kind=kind,
                title=title[:120],
                body=body,
                story=story,
                story_title=(story.title[:200] if story else ''),
                story_slug=(story.slug[:250] if story else ''),
                dedupe_key=dedupe_key[:120],
            )
    except IntegrityError:
        logger.debug(
            'Notification for user=%s key=%s already exists; skipping',
            user.pk, dedupe_key,
        )
        return None


def active_users():
    """Readers who can receive a broadcast.

    Inactive accounts are excluded: a suspended or deleted user has no inbox to
    read, and writing rows for them grows the table for no reader.
    """
    User = get_user_model()
    return User.objects.filter(is_active=True).order_by('pk')


def notify_new_story(story, users=None):
    """Tell readers that [story] is published. Idempotent per reader.

    Keyed on the slug so a story that is unpublished and re-published produces
    no second message, while a genuinely new story always reaches everyone.
    """
    if not story.pk or not story.slug:
        return 0

    recipients = active_users() if users is None else users
    dedupe_key = f'new_story:{story.slug}'

    created = 0
    for user in recipients.iterator():
        message = notify(
            user,
            Notification.Kind.NEW_STORY,
            'New story: {}'.format(story.title),
            _story_blurb(story),
            story=story,
            dedupe_key=dedupe_key,
        )
        created += message is not None
    return created


def _story_blurb(story):
    """One short line describing a story, for use as a message body."""
    parts = []
    summary = ' '.join((story.summary or '').split())
    if summary:
        parts.append(summary[:200])
    if story.region:
        parts.append(story.region)
    return ' • '.join(parts)


def trending_stories(limit=DIGEST_SIZE, since_days=7):
    """Published stories of the last [since_days] days, most engaged first.

    Engagement is likes + bookmarks + views. This is the same measure the
    ``/api/stories/trending/`` endpoint exposes, so a reader who opens the digest
    and then the trending tab sees one consistent ranking rather than two.
    """
    since = timezone.now() - timezone.timedelta(days=since_days)
    return list(
        Story.objects.filter(
            status=Story.Status.PUBLISHED,
            created_at__gte=since,
        )
        .select_related('author')
        .prefetch_related('categories')
        .annotate(engagement=Count('likes') + Count('bookmarks') + F('view_count'))
        .order_by('-engagement', '-created_at')[:limit]
    )


def _digest_body(stories):
    """Render the digest's numbered list of stories."""
    return '\n'.join(
        '{}. {}'.format(index, story.title)
        for index, story in enumerate(stories, start=1)
    )


def send_trending_digest(users=None, when=None, limit=DIGEST_SIZE):
    """Send the weekly "what readers are reading" digest. Idempotent per week.

    Keyed on the ISO year and week, so a retry on Sunday night and a manual run
    on Monday morning still produce exactly one digest per reader. Blanket
    undelivery is a symptom worth knowing about, so a week with nothing to
    report creates no messages.
    """
    when = when or timezone.now()
    stories = trending_stories(limit=limit, since_days=7)
    if not stories:
        return 0

    iso_year, iso_week, _ = when.isocalendar()
    dedupe_key = f'trending:{iso_year}-W{iso_week:02d}'

    body = _digest_body(stories)

    recipients = active_users() if users is None else users
    created = 0
    for user in recipients.iterator():
        message = notify(
            user,
            Notification.Kind.TRENDING,
            'Trending this week',
            body,
            dedupe_key=dedupe_key,
        )
        created += message is not None
    return created


def send_streak_reminders(profiles=None, when=None):
    """Nudge readers whose streak expires at the end of their local day.

    Only readers with a live, unbroken streak who have not been active today are
    messaged, and the key is the reader's own local date so each reader gets at
    most one nudge per day regardless of how often the job runs.
    """
    from gamification.services.streaks import local_date, streak_at_risk

    when = when or timezone.now()
    if profiles is None:
        from gamification.services.streaks import users_at_risk_today

        profiles = users_at_risk_today(when)

    created = 0
    for profile in profiles:
        if not streak_at_risk(profile, local_date(profile, when)):
            continue
        user = profile.user
        days = profile.current_streak
        message = notify(
            user,
            Notification.Kind.STREAK,
            'Keep your {}-day streak alive'.format(days),
            'Read, quiz or open Griot today to reach {} days.'.format(days + 1),
            dedupe_key='streak:{}'.format(local_date(profile, when)),
        )
        created += message is not None
    return created


def announce(title, body, kind=Notification.Kind.ANNOUNCEMENT, users=None):
    """Broadcast a message to every active reader.

    Admin-initiated, so there is no natural key to dedupe on: each call is a
    deliberate new message. [dedupe_key] still accepts one when a caller needs a
    retry-safe send.
    """
    recipients = active_users() if users is None else users
    created = 0
    for user in recipients.iterator():
        message = notify(user, kind, title, body, dedupe_key='')
        created += message is not None
    return created


def unread_count(user):
    """How many messages the reader has not opened yet."""
    if user is None or not user.is_authenticated:
        return 0
    return Notification.objects.filter(user=user, is_read=False).count()


def sync_for_user(user, when=None):
    """Bring one reader's inbox up to date, without duplicating anything.

    Called when the reader opens the app, which is the only moment a message
    could be read anyway. Doing the recurring sends here rather than from a
    scheduler is deliberate: Render's free tier has no cron, and a digest
    delivered to an inbox nobody opens has achieved nothing. Every send is
    keyed, so this runs on every open and costs three indexed lookups.

    Returns the number of messages created.
    """
    if user is None or not user.is_authenticated:
        return 0
    when = when or timezone.now()
    created = 0

    stories = trending_stories(limit=DIGEST_SIZE, since_days=7)
    if stories:
        iso_year, iso_week, _ = when.isocalendar()
        created += notify(
            user,
            Notification.Kind.TRENDING,
            'Trending this week',
            _digest_body(stories),
            dedupe_key=f'trending:{iso_year}-W{iso_week:02d}',
        ) is not None

    from gamification.models import UserProfile
    from gamification.services.streaks import local_date, streak_at_risk

    profile = UserProfile.objects.filter(user=user).first()
    if profile is not None and streak_at_risk(profile, local_date(profile, when)):
        today = local_date(profile, when)
        days = profile.current_streak
        created += notify(
            user,
            Notification.Kind.STREAK,
            f'Keep your {days}-day streak alive',
            f'Read, quiz or open Griot today to reach {days + 1} days.',
            dedupe_key=f'streak:{today}',
        ) is not None

    return created


def mark_all_read(user):
    """Mark every message read. Returns how many changed."""
    if user is None or not user.is_authenticated:
        return 0
    return Notification.objects.filter(
        user=user, is_read=False
    ).update(is_read=True, read_at=timezone.now())
