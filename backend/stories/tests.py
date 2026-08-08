from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import ReadingProgress, Story, StoryCategory, StoryBookmark, StoryLike, StoryFlag

User = get_user_model()


class StoryCategoryTests(APITestCase):
    def setUp(self):
        self.category = StoryCategory.objects.create(
            name='Folktales',
            description='Traditional folktales',
            icon='📚',
        )

    def test_list_categories(self):
        url = reverse('stories:category-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Check that our category is in the results (paginated or list)
        data = resp.data.get('results', resp.data) if isinstance(resp.data, dict) else resp.data
        names = [c['name'] for c in data]
        self.assertIn('Folktales', names)

    def test_retrieve_category_by_slug(self):
        url = reverse('stories:category-detail', kwargs={'slug': 'folktales'})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['name'], 'Folktales')


class StoryTests(APITestCase):
    def setUp(self):
        self.contributor = User.objects.create_user(
            'contributor1',
            email='contrib1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.visitor = User.objects.create_user(
            'visitor1',
            email='visitor1@example.com',
            password='hunter2secure',
            role='visitor',
        )
        self.category = StoryCategory.objects.create(
            name='Proverbs',
            icon='💬',
        )
        self.story = Story.objects.create(
            title='The Tortoise and the Hare',
            content='Once upon a time in the forests of Cameroon, there lived a wise tortoise...',
            summary='A classic tale about patience and perseverance.',
            author=self.contributor,
            language='en',
            region='Northwest Region',
            tags='folktale,wisdom,patience',
            status=Story.Status.PUBLISHED,
        )
        self.story.categories.add(self.category)
        self.draft_story = Story.objects.create(
            title='Draft Story',
            content='This is a draft that should not be visible to visitors.',
            author=self.contributor,
            status=Story.Status.DRAFT,
        )

    def test_list_published_stories(self):
        """Anonymous users should see only published stories."""
        url = reverse('stories:story-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Should only see published story
        self.assertEqual(len(resp.data['results']), 1)
        self.assertEqual(resp.data['results'][0]['title'], 'The Tortoise and the Hare')

    def test_contributor_sees_own_drafts(self):
        """Contributors should see their own drafts in the list."""
        self.client.force_authenticate(self.contributor)
        url = reverse('stories:story-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Should see both published and own draft
        titles = [s['title'] for s in resp.data['results']]
        self.assertIn('The Tortoise and the Hare', titles)
        self.assertIn('Draft Story', titles)

    def test_retrieve_story_detail(self):
        url = reverse('stories:story-detail', kwargs={'slug': 'the-tortoise-and-the-hare'})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['title'], 'The Tortoise and the Hare')
        self.assertIn('content', resp.data)
        self.assertEqual(resp.data['author']['username'], 'contributor1')

    def test_create_story_requires_authentication(self):
        url = reverse('stories:story-list')
        resp = self.client.post(url, {
            'title': 'New Story',
            'content': 'A wonderful new story about African heritage.',
        })
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_visitor_cannot_create_story(self):
        self.client.force_authenticate(self.visitor)
        url = reverse('stories:story-list')
        resp = self.client.post(url, {
            'title': 'New Story',
            'content': 'A wonderful new story about African heritage.',
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_contributor_can_create_story(self):
        self.client.force_authenticate(self.contributor)
        url = reverse('stories:story-list')
        resp = self.client.post(url, {
            'title': 'The Wise Spider',
            'content': 'In the village of Bafut, there was a spider known for its wisdom.',
            'summary': 'A spider teaches the village about cleverness.',
            'language': 'en',
            'region': 'Bafut',
            'tags': 'spider,wisdom',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['title'], 'The Wise Spider')

    def test_search_stories(self):
        url = reverse('stories:story-list')
        resp = self.client.get(url, {'search': 'Tortoise'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)

    def test_filter_by_language(self):
        Story.objects.create(
            title='French Story',
            content='Une histoire en français.',
            author=self.contributor,
            language='fr',
            status=Story.Status.PUBLISHED,
        )
        url = reverse('stories:story-list')
        resp = self.client.get(url, {'language': 'fr'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)
        self.assertEqual(resp.data['results'][0]['language'], 'fr')

    def test_filter_by_category(self):
        url = reverse('stories:story-list')
        resp = self.client.get(url, {'category': 'proverbs'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)


class StoryInteractionsTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'reader1',
            email='reader1@example.com',
            password='hunter2secure',
        )
        self.contributor = User.objects.create_user(
            'author1',
            email='author1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for interactions.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.client.force_authenticate(self.user)

    def test_toggle_bookmark(self):
        url = reverse('stories:story-bookmark', kwargs={'slug': 'test-story'})
        # First bookmark
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(resp.data['bookmarked'])
        self.assertTrue(StoryBookmark.objects.filter(user=self.user, story=self.story).exists())

        # Toggle off
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['bookmarked'])
        self.assertFalse(StoryBookmark.objects.filter(user=self.user, story=self.story).exists())

    def test_toggle_like(self):
        url = reverse('stories:story-like', kwargs={'slug': 'test-story'})
        # First like
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(resp.data['liked'])

        # Toggle off
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['liked'])

    def test_flag_story(self):
        url = reverse('stories:story-flag', kwargs={'slug': 'test-story'})
        resp = self.client.post(url, {
            'reason': 'cultural_inaccuracy',
            'details': 'The story misrepresents traditional customs.',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(StoryFlag.objects.filter(user=self.user, story=self.story).exists())

    def test_update_reading_progress(self):
        url = reverse('stories:story-progress', kwargs={'slug': 'test-story'})
        resp = self.client.post(url, {
            'progress_percent': 50,
            'last_position': 1000,
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['progress_percent'], 50)

    def test_my_stories(self):
        self.client.force_authenticate(self.contributor)
        url = reverse('stories:story-my')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)

    def test_bookmarks_list(self):
        StoryBookmark.objects.create(user=self.user, story=self.story)
        url = reverse('stories:story-bookmarks')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)

    def test_recently_read(self):
        ReadingProgress.objects.create(
            user=self.user,
            story=self.story,
            progress_percent=45,
        )
        url = reverse('stories:story-recently-read')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['progress_percent'], 45)

    def test_continue_reading(self):
        ReadingProgress.objects.create(
            user=self.user,
            story=self.story,
            progress_percent=30,
            completed=False,
        )
        url = reverse('stories:story-continue-reading')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)

    def test_continue_reading_excludes_completed(self):
        ReadingProgress.objects.create(
            user=self.user,
            story=self.story,
            progress_percent=100,
            completed=True,
        )
        url = reverse('stories:story-continue-reading')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 0)

    def test_share_story(self):
        url = reverse('stories:story-share', kwargs={'slug': 'test-story'})
        resp = self.client.post(url, {'platform': 'twitter'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('share_url', resp.data)
        self.assertIn('share_text', resp.data)
        self.story.refresh_from_db()
        self.assertEqual(self.story.share_count, 1)

    def test_trending_stories(self):
        url = reverse('stories:story-trending')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_popular_stories(self):
        url = reverse('stories:story-popular')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_discover_stories(self):
        url = reverse('stories:story-discover')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)


class ModerationTests(APITestCase):
    """Admin moderation queue & moderation actions."""

    def setUp(self):
        self.visitor = User.objects.create_user(
            'visitor1', email='visitor1@test.com', password='pass123', role='visitor'
        )
        self.manager = User.objects.create_user(
            'manager1', email='manager1@test.com', password='pass123',
            role='institution_manager',
        )
        self.admin = User.objects.create_user(
            'admin1', email='admin1@test.com', password='pass123', role='admin'
        )
        self.author = User.objects.create_user(
            'author1', email='author1@test.com', password='pass123',
            role='contributor',
        )
        self.reporter = User.objects.create_user(
            'reporter1', email='reporter1@test.com', password='pass123'
        )
        self.story = Story.objects.create(
            title='The Flagged Tale',
            content='Content that was flagged for review.',
            author=self.author,
            status=Story.Status.PUBLISHED,
        )
        self.flag = StoryFlag.objects.create(
            user=self.reporter,
            story=self.story,
            reason='cultural_inaccuracy',
            details='Misrepresents traditional customs.',
        )

    def test_moderation_queue_requires_admin_or_manager(self):
        url = reverse('stories:story-moderation-queue')

        # Anonymous denied
        resp = self.client.get(url)
        self.assertIn(resp.status_code, (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN))

        # Visitor denied
        self.client.force_authenticate(self.visitor)
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

        # Manager allowed
        self.client.force_authenticate(self.manager)
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_moderation_queue_lists_flagged_stories(self):
        self.client.force_authenticate(self.admin)
        url = reverse('stories:story-moderation-queue')
        resp = self.client.get(url)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)
        entry = resp.data[0]
        self.assertEqual(entry['title'], 'The Flagged Tale')
        self.assertEqual(entry['slug'], self.story.slug)
        self.assertEqual(entry['status'], 'published')
        self.assertEqual(entry['author_username'], 'author1')
        self.assertEqual(len(entry['flags']), 1)
        flag = entry['flags'][0]
        self.assertEqual(flag['reason'], 'cultural_inaccuracy')
        self.assertEqual(flag['reason_display'], 'Cultural Inaccuracy')
        self.assertEqual(flag['reporter'], 'reporter1')

    def test_moderation_queue_excludes_resolved_flags(self):
        self.flag.resolved = True
        self.flag.save()

        self.client.force_authenticate(self.admin)
        url = reverse('stories:story-moderation-queue')
        resp = self.client.get(url)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 0)

    def test_moderate_remove_archives_and_resolves_flags(self):
        self.client.force_authenticate(self.admin)
        url = reverse('stories:story-moderate', kwargs={'slug': self.story.slug})
        resp = self.client.post(url, {
            'action': 'remove',
            'notes': 'Removed for cultural inaccuracy.',
        })

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'archived')
        self.assertEqual(resp.data['resolved_flags'], 1)

        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.ARCHIVED)
        self.flag.refresh_from_db()
        self.assertTrue(self.flag.resolved)
        self.assertEqual(self.flag.resolution_notes, 'Removed for cultural inaccuracy.')

    def test_moderate_dismiss_keeps_story_published(self):
        self.client.force_authenticate(self.manager)
        url = reverse('stories:story-moderate', kwargs={'slug': self.story.slug})
        resp = self.client.post(url, {'action': 'dismiss'})

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'published')

        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.PUBLISHED)
        self.flag.refresh_from_db()
        self.assertTrue(self.flag.resolved)

    def test_moderate_rejects_invalid_action(self):
        self.client.force_authenticate(self.admin)
        url = reverse('stories:story-moderate', kwargs={'slug': self.story.slug})
        resp = self.client.post(url, {'action': 'ban'})

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.flag.refresh_from_db()
        self.assertFalse(self.flag.resolved)