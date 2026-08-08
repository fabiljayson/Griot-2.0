"""Tests for Phase 10 data-seeding management commands."""

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import TestCase

from gamification.models import Badge, Quiz
from qr_codes.models import Artifact
from stories.models import Story, StoryCategory

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
