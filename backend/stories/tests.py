from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
)

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
        self.story.refresh_from_db()
        self.assertEqual(self.story.bookmark_count, 1)

        # Toggle off
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['bookmarked'])
        self.assertFalse(StoryBookmark.objects.filter(user=self.user, story=self.story).exists())
        self.story.refresh_from_db()
        self.assertEqual(self.story.bookmark_count, 0)

    def test_toggle_like(self):
        url = reverse('stories:story-like', kwargs={'slug': 'test-story'})
        # First like
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(resp.data['liked'])
        self.story.refresh_from_db()
        self.assertEqual(self.story.like_count, 1)

        # Toggle off
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['liked'])
        self.story.refresh_from_db()
        self.assertEqual(self.story.like_count, 0)

    def test_like_count_across_multiple_users(self):
        other = User.objects.create_user('reader2', password='hunter2secure')
        url = reverse('stories:story-like', kwargs={'slug': 'test-story'})
        self.client.post(url)
        self.client.force_authenticate(other)
        self.client.post(url)
        self.story.refresh_from_db()
        self.assertEqual(self.story.like_count, 2)

        self.client.force_authenticate(self.user)
        self.client.post(url)
        self.story.refresh_from_db()
        self.assertEqual(self.story.like_count, 1)

    def test_like_decrement_floors_at_zero(self):
        # Drifted counter: a like row exists while like_count reads 0. The
        # decrement must clamp at zero in SQL, never write a negative value.
        StoryLike.objects.create(user=self.user, story=self.story)
        Story.objects.filter(pk=self.story.pk).update(like_count=0)
        url = reverse('stories:story-like', kwargs={'slug': 'test-story'})
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.like_count, 0)

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

class StoryProvenanceTests(APITestCase):
    """The app renders oral traditions it did not record.

    These tests pin the guarantees a reader depends on: seeded content is
    labelled as such, a withheld consent blocks publication, and a contributor
    cannot self-declare that a community agreed.
    """

    def setUp(self):
        self.contributor = User.objects.create_user(
            'prov_contributor',
            email='prov_contrib@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='The Calabash of Truth',
            content='A tale carried by the Mambila.',
            source='The Mambila',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
            origin=Story.Origin.COMMUNITY_RECORDED,
            rights_holder='The Mambila community',
            licence=Story.Licence.CC_BY_NC,
        )

    def test_publishing_with_withheld_consent_is_refused(self):
        self.story.consent_status = Story.Consent.WITHHELD
        with self.assertRaises(ValidationError):
            self.story.save()

        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.PUBLISHED)

    def test_withheld_consent_blocks_the_draft_to_published_transition(self):
        self.story.status = Story.Status.DRAFT
        self.story.save()
        self.story.consent_status = Story.Consent.WITHHELD
        self.story.status = Story.Status.PUBLISHED

        with self.assertRaises(ValidationError):
            self.story.save()

        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.DRAFT)

    def test_consent_can_be_restored_before_publishing(self):
        self.story.status = Story.Status.DRAFT
        self.story.consent_status = Story.Consent.WITHHELD
        self.story.save()

        # The fix path must work: reversing the consent decision unblocks it.
        self.story.consent_status = Story.Consent.GRANTED
        self.story.status = Story.Status.PUBLISHED
        self.story.save()
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.PUBLISHED)

    def test_withheld_consent_story_can_still_be_archived(self):
        self.story.consent_status = Story.Consent.WITHHELD
        self.story.status = Story.Status.ARCHIVED
        self.story.save()
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.ARCHIVED)

    def test_attribution_credits_source_and_rights_holder(self):
        self.assertEqual(
            self.story.attribution,
            'Told by The Mambila · Rights: The Mambila community',
        )

    def test_attribution_omits_a_duplicate_rights_holder(self):
        self.story.rights_holder = self.story.source
        self.assertEqual(self.story.attribution, 'Told by The Mambila')

    def test_seeded_origin_is_flagged_as_synthetic(self):
        self.assertFalse(self.story.is_synthetic_origin)
        self.story.origin = Story.Origin.SEEDED
        self.assertTrue(self.story.is_synthetic_origin)
        # Seeded content is not "told by" anyone, so the claim is dropped
        # while the source name is still shown.
        self.assertNotIn('Told by', self.story.attribution)
        self.assertIn('The Mambila', self.story.attribution)

    def test_detail_api_exposes_provenance_and_rights(self):
        resp = self.client.get(
            reverse('stories:story-detail', kwargs={'slug': self.story.slug})
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['origin'], Story.Origin.COMMUNITY_RECORDED)
        self.assertEqual(resp.data['licence'], Story.Licence.CC_BY_NC)
        self.assertEqual(resp.data['rights_holder'], 'The Mambila community')
        self.assertEqual(resp.data['consent_status'], Story.Consent.NOT_REQUESTED)
        self.assertIn('Mambila', resp.data['attribution'])
        self.assertFalse(resp.data['is_synthetic_origin'])

    def test_list_api_labels_seeded_stories(self):
        seeded = Story.objects.create(
            title='Sample Story',
            content='Demo content.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
            origin=Story.Origin.SEEDED,
        )
        resp = self.client.get(reverse('stories:story-list'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data.get('results', resp.data)
        by_id = {row['id']: row for row in data}
        self.assertTrue(by_id[seeded.id]['is_synthetic_origin'])
        self.assertFalse(by_id[self.story.id]['is_synthetic_origin'])

    def test_contributor_cannot_self_declare_consent(self):
        self.client.force_authenticate(self.contributor)
        resp = self.client.patch(
            reverse('stories:story-detail', kwargs={'slug': self.story.slug}),
            {'consent_status': Story.Consent.GRANTED},
            format='json',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(
            self.story.consent_status,
            Story.Consent.NOT_REQUESTED,
            'a contributor must not be able to record their own community\'s consent',
        )

    def test_contributor_can_declare_provenance(self):
        self.client.force_authenticate(self.contributor)
        resp = self.client.patch(
            reverse('stories:story-detail', kwargs={'slug': self.story.slug}),
            {
                'origin': Story.Origin.ORAL_TRANSCRIPTION,
                'provenance_notes': 'Transcribed from a Lamnso telling.',
                'licence': Story.Licence.CC_BY,
            },
            format='json',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.origin, Story.Origin.ORAL_TRANSCRIPTION)
        self.assertEqual(self.story.licence, Story.Licence.CC_BY)


class StorySubmissionTests(APITestCase):
    """Phase 4 — submitting for review, and seeing why you were rejected.

    `status` was read-only in the API while the web form passed it straight
    through, so the Flutter client's "submit for review" button sent
    `status: 'pending'` and had it silently discarded: the story stayed a draft
    and the UI reported success. Making it writable reopens the question it was
    read-only to close — an author publishing their own story — which is why
    the rule now lives in `stories.services.resolve_status`.
    """

    def setUp(self):
        self.contributor = User.objects.create_user(
            'submitter', email='submitter@example.com', password='hunter2secure',
            role='contributor',
        )
        self.reader = User.objects.create_user(
            'reader9', email='reader9@example.com', password='hunter2secure',
        )
        self.manager = User.objects.create_user(
            'manager9', email='manager9@example.com', password='hunter2secure',
            role='institution_manager',
        )
        self.story = Story.objects.create(
            title='A Tale of the Forest',
            content='Once upon a time in the forests of Cameroon...',
            author=self.contributor,
            status=Story.Status.DRAFT,
        )
        self.url = reverse('stories:story-detail', kwargs={'slug': self.story.slug})

    def test_contributor_can_submit_for_review(self):
        self.client.force_authenticate(self.contributor)
        resp = self.client.patch(self.url, {'status': 'pending'}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.PENDING)

    def test_a_contributor_cannot_publish_their_own_story(self):
        """The guard that must survive `status` becoming writable."""
        self.client.force_authenticate(self.contributor)
        resp = self.client.patch(self.url, {'status': 'published'}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(
            self.story.status,
            Story.Status.DRAFT,
            'an author must not be able to publish past the review queue',
        )

    def test_a_contributor_cannot_reject_or_archive_either(self):
        self.client.force_authenticate(self.contributor)
        for blocked in (Story.Status.REJECTED, Story.Status.ARCHIVED):
            self.client.patch(self.url, {'status': blocked}, format='json')
            self.story.refresh_from_db()
            self.assertEqual(self.story.status, Story.Status.DRAFT)

    def test_a_moderator_can_publish(self):
        self.client.force_authenticate(self.manager)
        resp = self.client.patch(self.url, {'status': 'published'}, format='json')

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.PUBLISHED)

    def test_a_stranger_cannot_change_the_status_at_all(self):
        self.client.force_authenticate(self.reader)
        resp = self.client.patch(self.url, {'status': 'pending'}, format='json')
        self.assertIn(
            resp.status_code,
            (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND),
        )
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.DRAFT)

    def test_the_web_form_follows_the_same_rule(self):
        """Constitution I: one rule, both surfaces. A contributor POSTing
        `published` at the web form must land on draft, exactly as the API
        coerces it."""
        from web.services import save_story

        story, _ = save_story(
            self.contributor,
            slug=None,
            title='Web Tale',
            content='Content.',
            summary='',
            language='en',
            region='',
            tags='',
            cultural_context='',
            moral_lesson='',
            source='',
            status=Story.Status.PUBLISHED,
            category_ids=[],
        )
        self.assertEqual(story.status, Story.Status.DRAFT)


class RejectionReasonTests(APITestCase):
    """The moderator writes a rejection reason and nobody ever read it — not in
    a serializer, not in a template, not in the Flutter model."""

    def setUp(self):
        self.author = User.objects.create_user(
            'author7', email='author7@example.com', password='hunter2secure',
            role='contributor',
        )
        self.reader = User.objects.create_user(
            'reader7', email='reader7@example.com', password='hunter2secure',
        )
        self.manager = User.objects.create_user(
            'manager7', email='manager7@example.com', password='hunter2secure',
            role='institution_manager',
        )
        self.story = Story.objects.create(
            title='Flagged Tale', content='Content.', author=self.author,
            status=Story.Status.PUBLISHED,
            reviewer_notes='Cite the source for the opening claim.',
        )
        self.url = reverse('stories:story-detail', kwargs={'slug': self.story.slug})

    def test_the_author_sees_the_note(self):
        self.client.force_authenticate(self.author)
        resp = self.client.get(self.url)
        self.assertEqual(resp.data['reviewer_notes'], 'Cite the source for the opening claim.')

    def test_a_moderator_sees_the_note(self):
        self.client.force_authenticate(self.manager)
        resp = self.client.get(self.url)
        self.assertEqual(resp.data['reviewer_notes'], 'Cite the source for the opening claim.')

    def test_a_stranger_does_not(self):
        self.client.force_authenticate(self.reader)
        resp = self.client.get(self.url)
        self.assertEqual(resp.data['reviewer_notes'], '')

    def test_an_anonymous_reader_does_not(self):
        resp = self.client.get(self.url)
        self.assertEqual(resp.data['reviewer_notes'], '')


class ConsentCaptureTests(APITestCase):
    """Two steps, deliberately: the author records that they *asked*, only a
    moderator records what the community *answered*."""

    def setUp(self):
        self.author = User.objects.create_user(
            'author8', email='author8@example.com', password='hunter2secure',
            role='contributor',
        )
        self.other = User.objects.create_user(
            'other8', email='other8@example.com', password='hunter2secure',
            role='contributor',
        )
        self.manager = User.objects.create_user(
            'manager8', email='manager8@example.com', password='hunter2secure',
            role='institution_manager',
        )
        self.story = Story.objects.create(
            title='A Living Tradition', content='Content.', author=self.author,
            status=Story.Status.PUBLISHED,
        )
        self.ask_url = reverse(
            'stories:story-request-consent', kwargs={'slug': self.story.slug},
        )
        self.answer_url = reverse(
            'stories:story-record-consent', kwargs={'slug': self.story.slug},
        )

    def test_the_author_records_that_they_asked(self):
        self.client.force_authenticate(self.author)
        resp = self.client.post(self.ask_url)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.PENDING)

    def test_asking_twice_changes_nothing(self):
        self.client.force_authenticate(self.author)
        self.client.post(self.ask_url)
        self.client.post(self.ask_url)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.PENDING)

    def test_another_contributor_cannot_ask_on_your_behalf(self):
        self.client.force_authenticate(self.other)
        resp = self.client.post(self.ask_url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.NOT_REQUESTED)

    def test_a_contributor_cannot_record_the_answer(self):
        self.client.force_authenticate(self.author)
        resp = self.client.post(
            self.answer_url,
            {'status': 'granted', 'basis': 'Said yes to me'},
        )
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.NOT_REQUESTED)

    def test_a_moderator_records_the_answer_with_attribution(self):
        self.client.force_authenticate(self.manager)
        resp = self.client.post(
            self.answer_url,
            {'status': 'granted', 'basis': 'Agreed by the family elder'},
        )

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.GRANTED)
        self.assertEqual(self.story.consent_basis, 'Agreed by the family elder')
        self.assertEqual(self.story.consent_attested_by, self.manager)
        self.assertIsNotNone(self.story.consent_attested_at)
        self.assertEqual(resp.data['consent_attested_by'], 'manager8')

    def test_a_status_without_a_basis_is_refused(self):
        """A consent status with no basis behind it cannot be defended later."""
        self.client.force_authenticate(self.manager)
        resp = self.client.post(self.answer_url, {'status': 'granted'})

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.story.refresh_from_db()
        self.assertEqual(self.story.consent_status, Story.Consent.NOT_REQUESTED)

    def test_withdrawing_consent_from_a_published_story_archives_it(self):
        """The model refuses to save published + withheld, so raising would mean
        consent could not be withdrawn at all. The record is kept, not deleted."""
        self.client.force_authenticate(self.manager)
        resp = self.client.post(
            self.answer_url,
            {'status': 'withheld', 'basis': 'The family withdrew permission'},
        )

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.ARCHIVED)
        self.assertEqual(self.story.consent_status, Story.Consent.WITHHELD)
        self.assertTrue(resp.data['archived'])

    def test_withdrawing_consent_from_a_draft_leaves_it_a_draft(self):
        self.story.status = Story.Status.DRAFT
        self.story.save(update_fields=['status'])

        self.client.force_authenticate(self.manager)
        resp = self.client.post(
            self.answer_url,
            {'status': 'withheld', 'basis': 'Withdrawn'},
        )

        self.story.refresh_from_db()
        self.assertEqual(self.story.status, Story.Status.DRAFT)
        self.assertFalse(resp.data['archived'])


class SeededProvenanceBackfillTests(TestCase):
    """Phase 4 task 4 — the 12 seeded stories said `origin='seeded'` and
    nothing else: empty provenance notes, empty rights holder, undetermined
    licence."""

    def _run_migration(self):
        import importlib

        from django.apps import apps

        module = importlib.import_module(
            'stories.migrations.0005_story_seeded_provenance_note',
        )
        module.backfill_seeded_provenance(apps, None)

    def test_fills_empty_notes_on_a_seeded_story(self):
        story = Story.objects.create(
            title='Seeded', content='x', author=self._author(),
            origin=Story.Origin.SEEDED,
        )
        self._run_migration()
        story.refresh_from_db()
        self.assertIn('Demonstration content', story.provenance_notes)
        self.assertIn('no community consent was sought', story.provenance_notes)

    def test_leaves_a_curated_story_alone(self):
        story = Story.objects.create(
            title='Curated', content='x', author=self._author(),
            origin=Story.Origin.ORAL_TRANSCRIPTION,
            provenance_notes='Told by Madame Ngo Bassong, 1998.',
        )
        self._run_migration()
        story.refresh_from_db()
        self.assertEqual(story.provenance_notes, 'Told by Madame Ngo Bassong, 1998.')

    def test_never_overwrites_a_moderators_own_note(self):
        story = Story.objects.create(
            title='Seeded but noted', content='x', author=self._author(),
            origin=Story.Origin.SEEDED,
            provenance_notes='Reviewed and confirmed as project-written.',
        )
        self._run_migration()
        story.refresh_from_db()
        self.assertEqual(story.provenance_notes, 'Reviewed and confirmed as project-written.')

    def test_is_idempotent(self):
        Story.objects.create(
            title='Seeded', content='x', author=self._author(),
            origin=Story.Origin.SEEDED,
        )
        self._run_migration()
        first = Story.objects.get(title='Seeded').provenance_notes
        self._run_migration()
        self.assertEqual(Story.objects.get(title='Seeded').provenance_notes, first)

    def _author(self):
        return User.objects.create_user(
            'provenance-author', email='prov@example.com',
            password='hunter2secure', role='contributor',
        )


class ConsentQueueTests(APITestCase):
    """The moderator worklist — the surface both consent forms hang off.

    Without it, `consent_status` was a field the server validated and no
    moderator could ever see or set: 12 seeded stories sat at
    `not_requested` with nothing anywhere in the product that listed them.
    """

    def setUp(self):
        self.author = User.objects.create_user(
            'queue-author', email='queue-author@example.com',
            password='hunter2secure', role='contributor',
        )
        self.manager = User.objects.create_user(
            'queue-manager', email='queue-manager@example.com',
            password='hunter2secure', role='institution_manager',
        )
        self.url = reverse('stories:story-consent-queue')

    def _story(self, title, consent_status, **kwargs):
        return Story.objects.create(
            title=title, content='Content.', author=self.author,
            consent_status=consent_status, **kwargs,
        )

    def test_a_contributor_cannot_read_the_queue(self):
        self._story('Waiting', Story.Consent.NOT_REQUESTED)
        self.client.force_authenticate(self.author)
        self.assertEqual(
            self.client.get(self.url).status_code, status.HTTP_403_FORBIDDEN,
        )

    def test_an_anonymous_visitor_cannot_read_the_queue(self):
        self._story('Waiting', Story.Consent.NOT_REQUESTED)
        self.assertEqual(
            self.client.get(self.url).status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_lists_stories_still_awaiting_a_decision(self):
        self._story('Never asked', Story.Consent.NOT_REQUESTED)
        self._story('Asked', Story.Consent.PENDING)

        self.client.force_authenticate(self.manager)
        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(
            sorted(row['title'] for row in resp.data), ['Asked', 'Never asked'],
        )

    def test_a_recorded_decision_leaves_the_queue(self):
        self._story('Answered', Story.Consent.GRANTED)
        self._story('Refused', Story.Consent.WITHHELD)
        self._story('Conditional', Story.Consent.GRANTED_RESTRICTED)

        self.client.force_authenticate(self.manager)
        resp = self.client.get(self.url)

        self.assertEqual(resp.data, [])

    def test_the_carries_everything_needed_to_make_the_decision(self):
        """A consent status recorded without these is a claim, not a record."""
        self._story(
            'Fully described', Story.Consent.PENDING,
            origin=Story.Origin.ORAL_TRANSCRIPTION,
            provenance_notes='Recorded in Bafoussam in 2019.',
            rights_holder='The Mambila community',
            licence=Story.Licence.CC_BY_NC,
            status=Story.Status.PENDING,
            region='West Region',
        )

        self.client.force_authenticate(self.manager)
        row = self.client.get(self.url).data[0]

        self.assertEqual(row['slug'], 'fully-described')
        self.assertEqual(row['author_username'], 'queue-author')
        self.assertEqual(row['origin'], Story.Origin.ORAL_TRANSCRIPTION)
        self.assertIn('Bafoussam', row['provenance_notes'])
        self.assertEqual(row['rights_holder'], 'The Mambila community')
        self.assertEqual(row['licence'], Story.Licence.CC_BY_NC)
        self.assertEqual(row['status'], Story.Status.PENDING)
        self.assertTrue(row['created_at'])

    def test_recording_an_answer_clears_the_story_from_the_queue(self):
        """The end-to-end path the screen exists for."""
        story = self._story('Waiting', Story.Consent.PENDING)
        self.client.force_authenticate(self.manager)

        self.client.get(self.url)
        resp = self.client.post(
            reverse(
                'stories:story-record-consent', kwargs={'slug': story.slug},
            ),
            {'status': 'granted', 'basis': 'Agreed by the family elder'},
        )

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(self.client.get(self.url).data, [])


class ConsentDecisionSetTests(APITestCase):
    """A moderator records an *answer*, so a non-answer must be refused.

    `not_requested` and `pending` are the absence of a decision. Validating
    against `Story.Consent.choices` accepted both, so a moderator could file
    "not requested" as what the community said — with a basis and an
    attestation attached — and the story would stay in the review queue, so the
    next moderator saw a decision that was not one.
    """

    def setUp(self):
        self.manager = User.objects.create_user(
            'decider9', email='decider9@example.com',
            password='hunter2secure', role='institution_manager',
        )
        self.story = Story.objects.create(
            title='A Tradition', content='Content.', author=self.manager,
            status=Story.Status.PUBLISHED,
        )
        self.answer_url = reverse(
            'stories:story-record-consent', kwargs={'slug': self.story.slug},
        )

    def _record(self, status_value):
        self.client.force_authenticate(self.manager)
        return self.client.post(
            self.answer_url,
            {'status': status_value, 'basis': 'Spoke to the family elder'},
        )

    def test_recording_not_requested_is_refused(self):
        resp = self._record('not_requested')

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.story.refresh_from_db()
        self.assertEqual(
            self.story.consent_status, Story.Consent.NOT_REQUESTED,
            '"not requested" is the absence of a decision, not one',
        )

    def test_recording_pending_is_refused(self):
        self._record('pending')

        resp = self.client.post(
            self.answer_url,
            {'status': 'pending', 'basis': 'Still waiting on a reply'},
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.story.refresh_from_db()
        self.assertNotEqual(
            self.story.consent_status, Story.Consent.PENDING,
            'a decision with an attestation behind it is a claim, not a wait',
        )

    def test_a_refused_decision_forges_no_attestation(self):
        """The dangerous half: a basis and a name must not stick either."""
        self._record('not_requested')

        self.story.refresh_from_db()
        self.assertIsNone(self.story.consent_attested_by)
        self.assertIsNone(self.story.consent_attested_at)
        self.assertEqual(self.story.consent_basis, '')

    def test_the_three_real_answers_are_all_accepted(self):
        from .services import CONSENT_DECISIONS

        for decision in CONSENT_DECISIONS:
            with self.subTest(decision=decision):
                self.story.refresh_from_db()
                self.story.consent_status = Story.Consent.PENDING
                self.story.save(update_fields=['consent_status'])

                resp = self._record(decision)
                self.assertEqual(
                    resp.status_code, status.HTTP_200_OK,
                    f'{decision} is a real answer and must be recordable',
                )

    def test_the_decision_set_is_exactly_the_three_answers(self):
        from .services import CONSENT_AWAITING_DECISION, CONSENT_DECISIONS

        self.assertEqual(
            set(CONSENT_DECISIONS),
            {Story.Consent.GRANTED, Story.Consent.GRANTED_RESTRICTED,
             Story.Consent.WITHHELD},
        )
        self.assertFalse(
            set(CONSENT_DECISIONS) & set(CONSENT_AWAITING_DECISION),
            'a state cannot be both awaiting a decision and a decision',
        )

    def test_an_unknown_status_still_names_the_value_it_refused(self):
        resp = self._record('maybe_one_day')

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        # The project exception handler nests field errors under `error`.
        detail = str(resp.data.get('error', resp.data))
        self.assertIn('consent_status', detail)
        self.assertIn(
            'maybe_one_day', detail,
            'the error must name the value refused — an f-string that wrote '
            '"{status}!r" rendered a literal "!r" instead of a repr',
        )
