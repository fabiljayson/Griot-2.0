"""Tests for Phase 10 data-seeding management commands."""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.db.models import Sum
from django.test import TestCase
from django.utils import timezone

from gamification.models import Badge, Quiz, UserProfile
from qr_codes.models import Artifact
from stories.models import Story, StoryCategory, StoryLike

User = get_user_model()


class SeedUsersTests(TestCase):
    def test_seed_users_creates_every_role(self):
        call_command('seed_users', verbosity=0)

        self.assertEqual(User.objects.filter(username='admin').count(), 1)
        self.assertEqual(
            User.objects.filter(username='demo_visitor', role='visitor').count(), 1
        )
        self.assertEqual(
            User.objects.filter(
                username='demo_contributor', role='contributor'
            ).count(),
            1,
        )
        self.assertEqual(
            User.objects.filter(
                username='demo_manager', role='institution_manager'
            ).count(),
            1,
        )

    def test_seed_users_is_idempotent(self):
        call_command('seed_users', verbosity=0)
        call_command('seed_users', verbosity=0)

        self.assertEqual(User.objects.count(), 4)


class SeedMockUsersTests(TestCase):
    databases = {'default', 'local'}

    def test_seed_mock_users_creates_engagement_and_is_idempotent(self):
        local_users = User.objects.db_manager('local')
        author = local_users.create_user(
            username='mock_seed_author',
            email='mock-seed-author@example.invalid',
            password='author-password',
            role='contributor',
        )
        stories = [
            Story.objects.using('local').create(
                title=f'Mock seed story {index}',
                content='A published story for mock engagement.',
                author=author,
            )
            for index in range(2)
        ]
        Story.objects.using('local').filter(
            pk__in=[story.pk for story in stories]
        ).update(status=Story.Status.PUBLISHED)

        call_command(
            'seed_mock_users',
            visitors=2,
            contributors=1,
            database='local',
            verbosity=0,
        )
        call_command(
            'seed_mock_users',
            visitors=2,
            contributors=1,
            database='local',
            verbosity=0,
        )

        self.assertEqual(
            User.objects.using('local').filter(email__startswith='mock_visitor_').count(),
            2,
        )
        self.assertEqual(
            User.objects.using('local').filter(email__startswith='mock_contributor_').count(),
            1,
        )
        mock_users = User.objects.using('local').filter(email__startswith='mock_')
        self.assertFalse(mock_users.filter(username__startswith='mock_').exists())
        self.assertFalse(mock_users.filter(first_name='Mock').exists())
        self.assertEqual(StoryLike.objects.using('local').count(), 3)
        self.assertEqual(
            Story.objects.using('local')
            .filter(pk__in=[story.pk for story in stories])
            .aggregate(total=Sum('view_count'))['total'],
            9,
        )
        profiles = UserProfile.objects.using('local').filter(
            user__email__startswith='mock_'
        )
        self.assertEqual(profiles.count(), 3)
        self.assertGreater(profiles.order_by('-total_xp').first().total_xp, 0)
        signup_dates = list(
            User.objects.using('local')
            .filter(email__startswith='mock_')
            .values_list('date_joined', flat=True)
        )
        self.assertTrue(
            all(joined_at >= timezone.now() - timedelta(days=30) for joined_at in signup_dates)
        )
        self.assertGreater(len({joined_at.date() for joined_at in signup_dates}), 1)


class SeedQrCodesTests(TestCase):
    def test_seed_qr_codes_creates_published_artifacts(self):
        call_command('seed_users', verbosity=0)
        call_command('seed_qr_codes', verbosity=0)

        self.assertEqual(Artifact.objects.count(), 6)
        self.assertTrue(all(a.is_published for a in Artifact.objects.all()))
        # Slugs are auto-generated from titles.
        self.assertTrue(Artifact.objects.filter(slug='bamoun-royal-mask').exists())

    def test_seed_qr_codes_is_idempotent(self):
        call_command('seed_qr_codes', verbosity=0)
        call_command('seed_qr_codes', verbosity=0)

        self.assertEqual(Artifact.objects.count(), 6)


class SeedAllTests(TestCase):
    def test_seed_all_populates_every_module(self):
        call_command('seed_all', verbosity=0)

        self.assertGreaterEqual(User.objects.count(), 4)
        self.assertGreater(Story.objects.count(), 0)
        self.assertGreater(StoryCategory.objects.count(), 0)
        self.assertGreater(Badge.objects.count(), 0)
        self.assertGreaterEqual(Artifact.objects.count(), 6)
        # Quizzes are created for the seeded published stories.
        self.assertGreater(Quiz.objects.count(), 0)
