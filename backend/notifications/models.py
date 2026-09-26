from django.conf import settings
from django.db import models
from django.db.models import Q


class Notification(models.Model):
    """A single message delivered to a single reader's inbox.

    Rows are per-user rather than per-event: an inbox has to record what *this*
    reader has already seen, so read state cannot live on a shared event. The
    fan-out that creates the rows is idempotent through [dedupe_key] — a new
    story re-published, or a weekly digest job that runs twice, cannot produce a
    second copy of the same message.
    """

    class Kind(models.TextChoices):
        NEW_STORY = 'new_story', 'New story'
        TRENDING = 'trending', 'Trending'
        STREAK = 'streak', 'Streak'
        BADGE = 'badge', 'Badge earned'
        ANNOUNCEMENT = 'announcement', 'Announcement'
        SYSTEM = 'system', 'System'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )

    kind = models.CharField(max_length=20, choices=Kind.choices)

    title = models.CharField(max_length=120)
    body = models.TextField(blank=True, default='')

    # The story is a *live* link, and the slug/title are a snapshot. A story
    # deleted after the message was sent must not erase the message, and the
    # reader still needs to know what it was about.
    story = models.ForeignKey(
        'stories.Story',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='notifications',
    )
    story_title = models.CharField(max_length=200, blank=True, default='')
    story_slug = models.CharField(max_length=250, blank=True, default='')

    # Blank means "no dedupe guarantee" (one-off messages such as a badge).
    # Otherwise at most one row per user may share a key.
    dedupe_key = models.CharField(max_length=120, blank=True, default='')

    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name_plural = 'Notifications'
        ordering = ('-created_at', '-id')
        constraints = [
            # Makes every fan-out safe to retry: the loser of a race is skipped
            # rather than shown a duplicate.
            models.UniqueConstraint(
                fields=('user', 'dedupe_key'),
                condition=~Q(dedupe_key=''),
                name='unique_notification_per_user_dedupe_key',
            ),
        ]
        indexes = [
            # The inbox query: this reader's messages, newest first.
            models.Index(fields=('user', '-created_at'), name='notif_inbox_idx'),
            # The unread badge: this reader's unread count.
            models.Index(fields=('user', 'is_read'), name='notif_unread_idx'),
        ]

    def __str__(self):
        return f'{self.user_id} — {self.kind}: {self.title}'

    def mark_read(self, commit=True):
        """Idempotently mark the message read, stamping the first read time."""
        if self.is_read:
            return False
        from django.utils import timezone

        self.is_read = True
        self.read_at = timezone.now()
        if commit:
            self.save(update_fields=['is_read', 'read_at'])
        return True
