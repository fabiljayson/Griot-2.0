"""
Tests for the admin analytics API endpoints.
"""
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from gamification.models import Quiz, QuizAttempt, UserProfile
from stories.models import Story, StoryCategory

User = get_user_model()


# Use direct URL paths since api/ urls don't have a namespace
DASHBOARD_URL = '/api/analytics/dashboard/'
USERS_URL = '/api/analytics/users/'
USERS_LIST_URL = '/api/analytics/users/list/'
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


class AdminUsersListTests(APITestCase):
    """The users-list endpoint shows every platform account to admins."""

    def setUp(self):
        self.visitor = User.objects.create_user(
            'visitor1', email='v1@test.com', password='pass123', role='visitor'
        )
        self.manager = User.objects.create_user(
            'manager1', email='m1@test.com', password='pass123',
            role='institution_manager',
        )
        self.admin = User.objects.create_user(
            'admin1', email='a1@test.com', password='pass123', role='admin'
        )

    def test_requires_admin_or_manager(self):
        resp = self.client.get(USERS_LIST_URL)
        self.assertIn(
            resp.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

        self.client.force_authenticate(self.visitor)
        resp = self.client.get(USERS_LIST_URL)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_returns_all_users_newest_first(self):
        self.client.force_authenticate(self.admin)
        resp = self.client.get(USERS_LIST_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 3)

        first = resp.data[0]
        self.assertIn('id', first)
        self.assertIn('username', first)
        self.assertIn('email', first)
        self.assertEqual(first['role_display'], 'Admin')
        self.assertIn('is_active', first)
        self.assertIn('date_joined', first)

    def test_search_filters_by_username_and_email(self):
        self.client.force_authenticate(self.admin)

        resp = self.client.get(USERS_LIST_URL, {'search': 'admin1'})
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['username'], 'admin1')

        resp = self.client.get(USERS_LIST_URL, {'search': 'm1@test.com'})
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['username'], 'manager1')

        resp = self.client.get(USERS_LIST_URL, {'search': 'no-such-user'})
        self.assertEqual(len(resp.data), 0)


class GamificationXpConsistencyTests(APITestCase):
    """The "XP earned" tile must agree with the leaderboard printed beneath it.

    These two sat on the same screen reading `QuizAttempt.xp_earned` and
    `UserProfile.total_xp` respectively, so a platform with XP in its profiles
    but no passed quiz attempts showed 0 above a leaderboard of ~2,000. Both
    numbers were true about different things; only one is "XP earned".
    """

    def setUp(self):
        self.user = User.objects.create_user(
            'xp_user', email='xp@example.com',
            password='hunter2secure', role='visitor',
        )
        self.profile = UserProfile.objects.create(
            user=self.user, total_xp=1500, level=12,
        )

    def test_total_xp_earned_is_the_platform_total(self):
        from api.analytics import get_gamification_stats

        stats = get_gamification_stats()
        self.assertEqual(stats['total_xp_earned'], 1500)

    def test_total_xp_earned_never_contradicts_the_top_reader(self):
        from api.analytics import get_gamification_stats

        stats = get_gamification_stats()
        best = max(u['total_xp'] for u in stats['top_users'])
        self.assertGreaterEqual(
            stats['total_xp_earned'], best,
            'the platform total cannot be smaller than the largest member',
        )

    def test_quiz_xp_is_reported_separately(self):
        from api.analytics import get_gamification_stats

        # `xp_reward` is derived (50 + 10 per question), so a quiz with no
        # questions pays exactly 50. A quiz belongs to a story.
        story = Story.objects.create(
            title='Quiz Host Story', content='Content.',
            author=self.user, status=Story.Status.PUBLISHED,
        )
        # One quiz per story, created automatically with the story.
        quiz = Quiz.objects.get(story=story)
        QuizAttempt.objects.create(
            user=self.user, quiz=quiz,
            status=QuizAttempt.Status.COMPLETED,
            passed=True, score=90, xp_earned=50,
        )
        stats = get_gamification_stats()
        self.assertEqual(stats['quiz_xp_earned'], 50)
        self.assertEqual(
            stats['total_xp_earned'], 1500,
            'the quiz payout is recorded on the profile, not summed separately',
        )


class DashboardGrowthSeriesTests(APITestCase):
    """The growth series must be correct *and* not cost 120 queries.

    Each series was a loop of 30 `COUNT(*)` calls, so the dashboard paid 120
    round trips to draw three sparklines. They are now one grouped query each.
    The budget assertion is the point: without it the loops can come back
    unnoticed, because a correct-but-slow series still passes every other test.
    """

    def test_each_growth_series_has_30_chronological_points(self):
        from api.analytics import get_qr_stats, get_user_stats

        for name, fn in (
            ('user_growth', get_user_stats),
            ('scan_growth', get_qr_stats),
        ):
            series = fn()[name]
            with self.subTest(series=name):
                self.assertEqual(len(series), 30)
                self.assertEqual(series, sorted(series, key=lambda p: p['date']))
                for point in series:
                    self.assertIn('count', point)

    def test_days_with_no_rows_are_present_with_zero(self):
        """A gap must render as a zero, not disappear and shift the axis."""
        from api.analytics import daily_growth

        series = daily_growth(User.objects.none(), 'date_joined', days=7)
        self.assertEqual(len(series), 7)
        self.assertTrue(all(point['count'] == 0 for point in series))

    def test_a_row_on_one_day_lands_on_that_day(self):
        from api.analytics import daily_growth

        user = User.objects.create_user(
            'growth_user', email='growth@example.com', password='hunter2secure',
        )
        today = timezone.now().date().isoformat()
        series = daily_growth(User.objects.filter(pk=user.pk), 'date_joined', days=30)
        by_date = {point['date']: point['count'] for point in series}
        self.assertEqual(by_date[today], 1)

    def test_the_dashboard_stays_within_its_query_budget(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        from web.services import admin_dashboard_data

        admin_dashboard_data()  # warm any lazy caches first
        with CaptureQueriesContext(connection) as ctx:
            admin_dashboard_data()

        self.assertLessEqual(
            len(ctx.captured_queries), 60,
            f'dashboard issued {len(ctx.captured_queries)} queries; the growth '
            f'series must stay grouped rather than looping per day',
        )
