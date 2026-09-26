"""The reader's inbox: what gets created, how often, and who can see it."""

from datetime import datetime, timedelta
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from gamification.models import UserProfile
from notifications import services
from notifications.models import Notification
from stories.models import Story

User = get_user_model()
WAT = ZoneInfo('Africa/Douala')


def at(year, month, day, hour=9, tz=WAT):
    return datetime(year, month, day, hour, tzinfo=tz)


class NotificationTestMixin:
    def make_user(self, username, role='visitor', is_active=True):
        return User.objects.create_user(
            username,
            email=f'{username}@example.com',
            password='hunter2secure',
            role=role,
            is_active=is_active,
        )

    def make_story(self, author, title='A Story', status=Story.Status.DRAFT, **kwargs):
        return Story.objects.create(
            title=title,
            content='A story body.',
            author=author,
            status=status,
            **kwargs,
        )


class NotifyTests(NotificationTestMixin, TestCase):
    def test_creates_a_message(self):
        user = self.make_user('reader')
        story = self.make_story(user, 'The Baobab')

        message = services.notify(
            user, Notification.Kind.NEW_STORY, 'New story', 'Body', story=story
        )

        self.assertIsNotNone(message)
        self.assertFalse(message.is_read)
        # The story is snapshotted so a later deletion cannot erase the message.
        self.assertEqual(message.story_title, 'The Baobab')
        self.assertEqual(message.story_slug, story.slug)

    def test_a_repeated_dedupe_key_is_skipped(self):
        user = self.make_user('reader')
        services.notify(user, Notification.Kind.NEW_STORY, 'One', dedupe_key='k')
        again = services.notify(user, Notification.Kind.NEW_STORY, 'Two',
                                dedupe_key='k')

        self.assertIsNone(again)
        self.assertEqual(Notification.objects.filter(user=user).count(), 1)

    def test_a_blank_dedupe_key_does_not_dedupe(self):
        """One-off messages such as a badge must not collapse into one."""
        user = self.make_user('reader')
        services.notify(user, Notification.Kind.BADGE, 'First')
        services.notify(user, Notification.Kind.BADGE, 'Second')

        self.assertEqual(Notification.objects.filter(user=user).count(), 2)

    def test_the_same_key_is_free_for_a_different_reader(self):
        one = self.make_user('one')
        two = self.make_user('two')
        services.notify(one, Notification.Kind.NEW_STORY, 'A', dedupe_key='k')
        services.notify(two, Notification.Kind.NEW_STORY, 'A', dedupe_key='k')

        self.assertEqual(Notification.objects.count(), 2)

    def test_an_anonymous_recipient_is_ignored(self):
        self.assertIsNone(services.notify(None, Notification.Kind.SYSTEM, 'x'))


class NewStoryFanOutTests(NotificationTestMixin, TestCase):
    def setUp(self):
        self.author = self.make_user('author', role='contributor')
        self.reader = self.make_user('reader')
        self.suspended = self.make_user('suspended', is_active=False)

    def test_every_active_reader_is_told_once(self):
        story = self.make_story(self.author, 'New Folktale')

        created = services.notify_new_story(story)

        # The author is active too, so two active accounts receive it.
        self.assertEqual(created, 2)
        self.assertEqual(
            Notification.objects.filter(
                kind=Notification.Kind.NEW_STORY
            ).count(),
            2,
        )

    def test_a_suspended_account_is_not_written_to(self):
        story = self.make_story(self.author, 'New Folktale')
        services.notify_new_story(story)

        self.assertFalse(
            Notification.objects.filter(user=self.suspended).exists()
        )

    def test_re_running_the_fan_out_creates_nothing_new(self):
        story = self.make_story(self.author, 'New Folktale')
        first = services.notify_new_story(story)
        second = services.notify_new_story(story)

        self.assertEqual(first, 2)
        self.assertEqual(second, 0)
        self.assertEqual(Notification.objects.count(), 2)

    def test_a_different_story_does_get_through(self):
        services.notify_new_story(self.make_story(self.author, 'First Tale'))
        services.notify_new_story(self.make_story(self.author, 'Second Tale'))

        self.assertEqual(Notification.objects.count(), 4)


class StoryPublishSignalTests(NotificationTestMixin, TestCase):
    """Publishing is the trigger; every other save is not."""

    def setUp(self):
        self.author = self.make_user('author', role='contributor')
        self.reader = self.make_user('reader')

    def test_publishing_announces_the_story(self):
        story = self.make_story(self.author, 'Freshly Published')

        with self.captureOnCommitCallbacks(execute=True):
            story.status = Story.Status.PUBLISHED
            story.save()

        self.assertTrue(
            Notification.objects.filter(
                kind=Notification.Kind.NEW_STORY, story_title='Freshly Published'
            ).exists()
        )

    def test_saving_an_already_published_story_does_not_re_announce(self):
        story = self.make_story(self.author, 'Already Out', Story.Status.PUBLISHED)
        with self.captureOnCommitCallbacks(execute=True):
            pass  # let the creation announcement fire
        Notification.objects.all().delete()

        with self.captureOnCommitCallbacks(execute=True):
            story.view_count = 10
            story.save()

        self.assertEqual(Notification.objects.count(), 0)

    def test_a_draft_saves_quietly(self):
        story = self.make_story(self.author, 'Still A Draft')

        with self.captureOnCommitCallbacks(execute=True):
            story.save()

        self.assertEqual(Notification.objects.count(), 0)

    def test_republishing_does_not_duplicate_the_announcement(self):
        story = self.make_story(self.author, 'Cycled')

        with self.captureOnCommitCallbacks(execute=True):
            story.status = Story.Status.PUBLISHED
            story.save()
        with self.captureOnCommitCallbacks(execute=True):
            story.status = Story.Status.ARCHIVED
            story.save()
        with self.captureOnCommitCallbacks(execute=True):
            story.status = Story.Status.PUBLISHED
            story.save()

        new_story_notices = Notification.objects.filter(
            kind=Notification.Kind.NEW_STORY, story_title='Cycled'
        )
        self.assertEqual(new_story_notices.count(), 2)  # one per active account


class TrendingDigestTests(NotificationTestMixin, TestCase):
    def setUp(self):
        self.reader = self.make_user('reader')
        self.author = self.make_user('author', role='contributor')

    def _publish(self, title, views=0):
        story = self.make_story(self.author, title, Story.Status.PUBLISHED)
        if views:
            Story.objects.filter(pk=story.pk).update(view_count=views)
        return story

    def test_a_quiet_week_sends_nothing(self):
        created = services.send_trending_digest(when=at(2026, 5, 4))

        self.assertEqual(created, 0)
        self.assertEqual(Notification.objects.count(), 0)

    def test_the_digest_lists_the_most_engaged_stories(self):
        self._publish('Quietly Read', views=1)
        self._publish('The Talked About One', views=50)

        services.send_trending_digest(when=at(2026, 5, 4))

        digest = Notification.objects.get(user=self.reader)
        self.assertEqual(digest.kind, Notification.Kind.TRENDING)
        self.assertIn('The Talked About One', digest.body)
        # Five slots, and the loudest story leads.
        self.assertTrue(digest.body.startswith('1. The Talked About One'))

    def test_one_digest_per_reader_per_week(self):
        self._publish('Something Popular', views=10)

        first = services.send_trending_digest(when=at(2026, 5, 4, 9))
        # A retry on the same day, and a second run later the same week.
        same_day = services.send_trending_digest(when=at(2026, 5, 4, 21))
        later = services.send_trending_digest(when=at(2026, 5, 6))

        self.assertEqual(first, 2)
        self.assertEqual(same_day, 0)
        self.assertEqual(later, 0)

    def test_the_next_week_sends_again(self):
        self._publish('Still Popular', views=10)

        services.send_trending_digest(when=at(2026, 5, 4))
        following = services.send_trending_digest(when=at(2026, 5, 11))

        self.assertEqual(following, 2)
        self.assertEqual(Notification.objects.count(), 4)


class StreakReminderTests(NotificationTestMixin, TestCase):
    def setUp(self):
        self.today = datetime(2026, 5, 6).date()
        self.author = self.make_user('author', role='contributor')

    def _profile(self, username, streak, days_ago):
        user = self.make_user(username)
        return UserProfile.objects.create(
            user=user,
            current_streak=streak,
            timezone='Africa/Douala',
            last_active_date=self.today - timedelta(days=days_ago),
        )

    def test_only_readers_with_an_outstanding_streak_are_reminded(self):
        pending = self._profile('pending', 4, 1)
        done = self._profile('done', 4, 0)
        broken = self._profile('broken', 4, 3)

        reminded = services.send_streak_reminders(when=at(2026, 5, 6))

        self.assertEqual(reminded, 1)
        message = Notification.objects.get()
        self.assertEqual(message.user, pending.user)
        self.assertIn('4-day streak', message.title)
        self.assertNotIn(done.user, Notification.objects.values_list('user', flat=True))
        self.assertNotIn(broken.user, Notification.objects.values_list('user', flat=True))

    def test_the_nudge_reaches_each_reader_once_per_day(self):
        self._profile('pending', 2, 1)

        first = services.send_streak_reminders(when=at(2026, 5, 6, 8))
        second = services.send_streak_reminders(when=at(2026, 5, 6, 20))

        self.assertEqual(first, 1)
        self.assertEqual(second, 0)

    def test_being_active_clears_the_nudge(self):
        profile = self._profile('pending', 2, 1)
        profile.last_active_date = self.today
        profile.save(update_fields=['last_active_date'])

        reminded = services.send_streak_reminders(when=at(2026, 5, 6))

        self.assertEqual(reminded, 0)


class AnnounceTests(NotificationTestMixin, TestCase):
    def test_reaches_every_active_reader(self):
        self.make_user('one')
        self.make_user('two')
        self.make_user('gone', is_active=False)
        self.users = {
            name: User.objects.get(username=name) for name in ('one', 'two')
        }

        created = services.announce('New release', 'Faster reading now.')

        self.assertEqual(created, 2)
        message = Notification.objects.filter(
            kind=Notification.Kind.ANNOUNCEMENT, user=self.users['one']
        ).get()
        self.assertEqual(message.title, 'New release')
        self.assertFalse(message.is_read)

    def test_each_call_is_a_new_message(self):
        self.make_user('one')
        services.announce('First', '')
        services.announce('Second', '')

        self.assertEqual(Notification.objects.count(), 2)


class InboxApiTests(NotificationTestMixin, APITestCase):
    def setUp(self):
        self.reader = self.make_user('reader')
        self.other = self.make_user('other')
        self.admin = self.make_user('boss', role='admin')
        services.notify(self.reader, Notification.Kind.SYSTEM, 'Mine')
        services.notify(self.other, Notification.Kind.SYSTEM, 'Theirs')

    def test_the_inbox_requires_authentication(self):
        response = self.client.get(reverse('notifications:notification-list'))

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_the_inbox_only_shows_the_callers_messages(self):
        self.client.force_authenticate(self.reader)

        response = self.client.get(reverse('notifications:notification-list'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        titles = [row['title'] for row in response.data['results']]
        self.assertEqual(titles, ['Mine'])

    def test_the_inbox_carries_the_unread_count(self):
        self.client.force_authenticate(self.reader)

        response = self.client.get(reverse('notifications:notification-list'))

        self.assertEqual(response.data['unread_count'], 1)

    def test_someone_elses_message_is_not_reachable(self):
        theirs = Notification.objects.get(user=self.other)
        self.client.force_authenticate(self.reader)

        response = self.client.get(
            reverse('notifications:notification-detail', args=[theirs.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_marking_read_clears_one_message(self):
        message = Notification.objects.get(user=self.reader)
        self.client.force_authenticate(self.reader)

        response = self.client.post(
            reverse('notifications:notification-mark-read', args=[message.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_read'])
        message.refresh_from_db()
        self.assertTrue(message.is_read)
        self.assertIsNotNone(message.read_at)

    def test_marking_read_twice_is_harmless(self):
        message = Notification.objects.get(user=self.reader)
        self.client.force_authenticate(self.reader)
        url = reverse('notifications:notification-mark-read', args=[message.pk])
        self.client.post(url)
        response = self.client.post(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_read'])

    def test_mark_all_read_clears_the_badge(self):
        services.notify(self.reader, Notification.Kind.SYSTEM, 'Second')
        self.client.force_authenticate(self.reader)

        response = self.client.post(
            reverse('notifications:notification-mark-all-read')
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['marked'], 2)
        self.assertEqual(response.data['unread_count'], 0)
        self.assertEqual(
            Notification.objects.filter(user=self.reader, is_read=False).count(), 0
        )

    def test_unread_count_endpoint(self):
        self.client.force_authenticate(self.reader)

        response = self.client.get(reverse('notifications:notification-unread-count'))

        self.assertEqual(response.data['unread_count'], 1)

    def test_messages_cannot_be_deleted(self):
        """The inbox is a log; a client that can delete it can also lie to it."""
        message = Notification.objects.get(user=self.reader)
        self.client.force_authenticate(self.reader)

        response = self.client.delete(
            reverse('notifications:notification-detail', args=[message.pk])
        )

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_a_message_cannot_be_made_unread_again(self):
        message = Notification.objects.get(user=self.reader)
        message.mark_read()
        self.client.force_authenticate(self.reader)

        response = self.client.patch(
            reverse('notifications:notification-detail', args=[message.pk]),
            {'is_read': False},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class BroadcastApiTests(NotificationTestMixin, APITestCase):
    def setUp(self):
        self.admin = self.make_user('boss', role='admin')
        self.reader = self.make_user('reader')
        self.url = reverse('notifications:notification-broadcast')

    def test_a_reader_cannot_broadcast(self):
        self.client.force_authenticate(self.reader)

        response = self.client.post(
            self.url, {'title': 'Hello', 'body': 'Everyone'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(Notification.objects.count(), 0)

    def test_an_admin_broadcast_reaches_readers(self):
        self.client.force_authenticate(self.admin)

        response = self.client.post(
            self.url, {'title': 'New release', 'body': 'Faster now.'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['created'], 2)
        self.assertTrue(
            Notification.objects.filter(
                user=self.reader, title='New release', is_read=False
            ).exists()
        )

    def test_a_title_is_required(self):
        self.client.force_authenticate(self.admin)

        response = self.client.post(self.url, {'body': 'No title'}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Notification.objects.count(), 0)


class ActivityEndpointTests(NotificationTestMixin, APITestCase):
    def setUp(self):
        self.reader = self.make_user('reader')
        self.profile = UserProfile.objects.create(user=self.reader)
        self.url = reverse('gamification:record-activity')

    def test_opening_the_app_counts_as_activity(self):
        self.client.force_authenticate(self.reader)

        with patch('django.utils.timezone.now', return_value=at(2026, 6, 1, 22)):
            response = self.client.post(self.url, {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['current_streak'], 1)
        self.assertTrue(response.data['active_today'])
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 1)

    def test_the_client_timezone_is_stored(self):
        self.client.force_authenticate(self.reader)

        with patch('django.utils.timezone.now', return_value=at(2026, 6, 1, 22)):
            response = self.client.post(
                self.url, {'timezone': 'America/New_York'}, format='json'
            )

        self.assertEqual(response.data['timezone'], 'America/New_York')

    def test_the_activity_ping_is_ignored_while_signed_out(self):
        response = self.client.post(self.url, {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_the_profile_reports_a_broken_streak_as_zero(self):
        self.profile.current_streak = 6
        self.profile.longest_streak = 6
        self.profile.last_active_date = datetime.now().date() - timedelta(days=5)
        self.profile.save()
        self.client.force_authenticate(self.reader)

        response = self.client.get(reverse('gamification:user-profile'))

        self.assertEqual(response.data['current_streak'], 0)
        self.assertEqual(response.data['longest_streak'], 6)
        self.assertFalse(response.data['active_today'])


class SyncOnOpenTests(NotificationTestMixin, TestCase):
    """The recurring sends also run per reader when they open the app."""

    def setUp(self):
        self.reader = self.make_user('reader')
        self.author = self.make_user('author', role='contributor')
        self.today = datetime(2026, 5, 6).date()

    def _publish(self, title, views=10):
        story = self.make_story(self.author, title, Story.Status.PUBLISHED)
        Story.objects.filter(pk=story.pk).update(view_count=views)
        return story

    def test_opening_the_app_delivers_the_digest(self):
        self._publish('Widely Read')

        created = services.sync_for_user(self.reader, when=at(2026, 5, 6))

        self.assertEqual(created, 1)
        digest = Notification.objects.get(
            user=self.reader, kind=Notification.Kind.TRENDING
        )
        self.assertIn('Widely Read', digest.body)

    def test_opening_the_app_twice_in_a_week_sends_one_digest(self):
        self._publish('Widely Read')

        services.sync_for_user(self.reader, when=at(2026, 5, 6, 8))
        second = services.sync_for_user(self.reader, when=at(2026, 5, 6, 20))

        self.assertEqual(second, 0)
        self.assertEqual(
            Notification.objects.filter(
                user=self.reader, kind=Notification.Kind.TRENDING
            ).count(),
            1,
        )

    def test_opening_the_app_delivers_the_streak_nudge(self):
        UserProfile.objects.create(
            user=self.reader,
            current_streak=6,
            timezone='Africa/Douala',
            last_active_date=self.today - timedelta(days=1),
        )

        services.sync_for_user(self.reader, when=at(2026, 5, 6))

        nudge = Notification.objects.get(
            user=self.reader, kind=Notification.Kind.STREAK
        )
        self.assertIn('6-day streak', nudge.title)

    def test_a_quiet_inbox_stays_quiet(self):
        created = services.sync_for_user(self.reader, when=at(2026, 5, 6))

        self.assertEqual(created, 0)
        self.assertEqual(Notification.objects.count(), 0)


class ActivityDeliversTheInboxTests(NotificationTestMixin, APITestCase):
    """The activity ping the app sends on open also flushes the inbox."""

    def setUp(self):
        self.reader = self.make_user('reader')
        self.author = self.make_user('author', role='contributor')
        self.url = reverse('gamification:record-activity')

    def test_opening_the_app_leaves_a_digest_waiting(self):
        story = self.make_story(
            self.author, 'Trending Now', Story.Status.PUBLISHED
        )
        Story.objects.filter(pk=story.pk).update(view_count=25)
        self.client.force_authenticate(self.reader)

        with patch('django.utils.timezone.now', return_value=at(2026, 6, 2, 9)):
            self.client.post(self.url, {}, format='json')

        self.assertTrue(
            Notification.objects.filter(
                user=self.reader, kind=Notification.Kind.TRENDING
            ).exists()
        )
