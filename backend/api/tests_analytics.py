"""
Tests for the admin analytics API endpoints.
"""
from django.contrib.auth import get_user_model
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from stories.models import Story, StoryCategory, StoryLike, StoryBookmark, StoryShare
from gamification.models import Quiz, QuizAttempt, UserProfile, UserBadge, Badge
from qr_codes.models import Artifact, QRCodeScan

User = get_user_model()


# Use direct URL paths since api/ urls don't have a namespace
DASHBOARD_URL = '/api/analytics/dashboard/'
USERS_URL = '/api/analytics/users/'
STORIES_URL = '/api/analytics/stories/'
GAMIFICATION_URL = '/api/analytics/gamification/'
QR_URL = '/api/analytics/qr-codes/'
ENGAGEMENT_URL = '/api/analytics/engagement/'


class AnalyticsPermissionTests(APITestCase):
    """Test that analytics endpoints require admin/manager role."""

    def setUp(self):
        self.visitor = User.objects.create_user(
            'visitor1', email='v1@test.com', password='pass123', role='visitor'
        )
        self.contributor = User.objects.create_user(
            'contributor1', email='c1@test.com', password='pass123', role='contributor'
        )
        self.manager = User.objects.create_user(
            'manager1', email='m1@test.com', password='pass123', role='institution_manager'
        )
        self.admin = User.objects.create_user(
            'admin1', email='a1@test.com', password='pass123', role='admin'
        )
        self.dashboard_url = DASHBOARD_URL

    def test_anonymous_user_denied(self):
        resp = self.client.get(self.dashboard_url)
        self.assertIn(resp.status_code, [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN])

    def test_visitor_denied(self):
        self.client.force_authenticate(self.visitor)
        resp = self.client.get(self.dashboard_url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_contributor_denied(self):
        self.client.force_authenticate(self.contributor)
        resp = self.client.get(self.dashboard_url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_manager_allowed(self):
        self.client.force_authenticate(self.manager)
        resp = self.client.get(self.dashboard_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_admin_allowed(self):
        self.client.force_authenticate(self.admin)
        resp = self.client.get(self.dashboard_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)


class AnalyticsDataTests(APITestCase):
    """Test that analytics return correct data."""

    def setUp(self):
        self.admin = User.objects.create_user(
            'admin1', email='a1@test.com', password='pass123', role='admin'
        )
        self.client.force_authenticate(self.admin)

        # Create test data
        self.contributor = User.objects.create_user(
            'contributor1', email='c1@test.com', password='pass123', role='contributor'
        )
        self.category = StoryCategory.objects.create(name='Folktales')
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story content.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
            view_count=100,
            like_count=25,
            bookmark_count=10,
            share_count=5,
        )

    def test_dashboard_summary_structure(self):
        """Dashboard should return all major sections."""
        resp = self.client.get(DASHBOARD_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('users', data)
        self.assertIn('stories', data)
        self.assertIn('gamification', data)
        self.assertIn('qr_codes', data)
        self.assertIn('engagement', data)

    def test_user_analytics(self):
        resp = self.client.get(USERS_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('total_users', data)
        self.assertGreaterEqual(data['total_users'], 2)  # admin + contributor
        self.assertIn('users_by_role', data)
        # Check that roles are tracked (contributor and admin at minimum)
        self.assertIn('contributor', data['users_by_role'])
        self.assertIn('admin', data['users_by_role'])
        self.assertIn('user_growth', data)

    def test_story_analytics(self):
        resp = self.client.get(STORIES_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('total_stories', data)
        self.assertGreaterEqual(data['total_stories'], 1)
        self.assertIn('engagement', data)
        self.assertEqual(data['engagement']['total_views'], 100)
        self.assertEqual(data['engagement']['total_likes'], 25)
        self.assertIn('top_stories', data)
        self.assertGreaterEqual(len(data['top_stories']), 1)

    def test_gamification_analytics_empty(self):
        resp = self.client.get(GAMIFICATION_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('total_quizzes_taken', data)
        self.assertEqual(data['total_quizzes_taken'], 0)

    def test_qr_analytics_empty(self):
        resp = self.client.get(QR_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('total_artifacts', data)
        self.assertEqual(data['total_artifacts'], 0)

    def test_engagement_analytics(self):
        resp = self.client.get(ENGAGEMENT_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertIn('total_likes', data)
        self.assertIn('total_bookmarks', data)
        self.assertIn('recent_activity_7d', data)

    def test_individual_endpoints_all_work(self):
        """Smoke test all individual analytics endpoints."""
        endpoints = [
            USERS_URL,
            STORIES_URL,
            GAMIFICATION_URL,
            QR_URL,
            ENGAGEMENT_URL,
        ]
        for url in endpoints:
            resp = self.client.get(url)
            self.assertEqual(
                resp.status_code, status.HTTP_200_OK,
                f'{url} returned {resp.status_code}'
            )
