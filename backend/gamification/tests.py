from datetime import datetime, timedelta
from unittest.mock import patch
from zoneinfo import ZoneInfo

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from stories.models import Story

from .models import Badge, Quiz, QuizAttempt, QuizQuestion, UserBadge, UserProfile
from .services import streaks
from .services.quiz_provisioner import ensure_quizzes_for_published_stories

User = get_user_model()


class QuizTests(APITestCase):
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
        # Built as a draft so the fixed two-question quiz below can be attached
        # before the story goes live: publishing auto-provisions a quiz, and a
        # story may only ever have one.
        self.story = Story.objects.create(
            title='The Wise Spider',
            content='A story about a clever spider.',
            author=self.contributor,
            status=Story.Status.DRAFT,
        )
        self.quiz = Quiz.objects.create(
            story=self.story,
            title='Test Quiz',
            passing_score=70,
        )
        self.question1 = QuizQuestion.objects.create(
            quiz=self.quiz,
            question_text='What animal is the story about?',
            option_a='Spider',
            option_b='Tortoise',
            option_c='Elephant',
            correct_answer='a',
            explanation='The story is about a spider.',
            order=1,
        )
        self.question2 = QuizQuestion.objects.create(
            quiz=self.quiz,
            question_text='Where does the story take place?',
            option_a='Forest',
            option_b='Village',
            option_c='River',
            correct_answer='b',
            explanation='The story takes place in a village.',
            order=2,
        )
        # Publishing must not disturb a quiz an editor already built.
        self.story.status = Story.Status.PUBLISHED
        self.story.save()

    def test_list_quizzes(self):
        url = reverse('gamification:quiz-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)

    def test_retrieve_quiz(self):
        url = reverse('gamification:quiz-detail', kwargs={'pk': self.quiz.id})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['questions']), 2)

    def test_start_quiz(self):
        self.client.force_authenticate(self.visitor)
        url = reverse('gamification:quiz-start', kwargs={'pk': self.quiz.id})
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'in_progress')

    def test_submit_answer(self):
        self.client.force_authenticate(self.visitor)
        # Start quiz
        start_url = reverse('gamification:quiz-start', kwargs={'pk': self.quiz.id})
        self.client.post(start_url)

        # Submit answer
        answer_url = reverse('gamification:quiz-submit-answer', kwargs={'pk': self.quiz.id})
        resp = self.client.post(answer_url, {
            'question_id': self.question1.id,
            'selected_answer': 'a',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['is_correct'])

    def test_finish_quiz(self):
        self.client.force_authenticate(self.visitor)
        # Start quiz
        start_url = reverse('gamification:quiz-start', kwargs={'pk': self.quiz.id})
        self.client.post(start_url)

        # Answer both questions correctly
        answer_url = reverse('gamification:quiz-submit-answer', kwargs={'pk': self.quiz.id})
        self.client.post(answer_url, {'question_id': self.question1.id, 'selected_answer': 'a'})
        self.client.post(answer_url, {'question_id': self.question2.id, 'selected_answer': 'b'})

        # Finish quiz
        finish_url = reverse('gamification:quiz-finish', kwargs={'pk': self.quiz.id})
        resp = self.client.post(finish_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['passed'])
        self.assertEqual(resp.data['score'], 100)

    def test_cannot_start_quiz_without_auth(self):
        url = reverse('gamification:quiz-start', kwargs={'pk': self.quiz.id})
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)


class BadgeTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'explorer',
            email='explorer@example.com',
            password='hunter2secure',
        )
        self.badge = Badge.objects.create(
            name='First Story',
            slug='first-story',
            description='Read your first story',
            emoji='📖',
            category='reading',
            stories_read_required=1,
        )
        self.secret_badge = Badge.objects.create(
            name='Secret Badge',
            slug='secret-badge',
            description='A hidden achievement',
            emoji='🔮',
            is_secret=True,
            xp_required=9999,
        )

    def test_list_badges(self):
        url = reverse('gamification:badge-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Secret badge should not appear for anonymous
        self.assertEqual(len(resp.data['results']), 1)

    def test_earn_badge(self):
        self.client.force_authenticate(self.user)
        UserBadge.objects.create(user=self.user, badge=self.badge)
        url = reverse('gamification:badge-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['results'][0]['earned'])


class UserProfileTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'player1',
            email='player1@example.com',
            password='hunter2secure',
        )

    def test_get_profile(self):
        self.client.force_authenticate(self.user)
        url = reverse('gamification:user-profile')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['level'], 1)
        self.assertEqual(resp.data['total_xp'], 0)

    def test_leaderboard(self):
        url = reverse('gamification:leaderboard')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)


class QuizGradingTests(APITestCase):
    def test_calculate_score(self):
        user = User.objects.create_user('test', email='t@t.com', password='pass')
        story = Story.objects.create(
            title='T', content='C',
            author=user, status=Story.Status.PUBLISHED,
        )
        quiz = story.quiz
        quiz.questions.all().delete()
        quiz.title = 'Q'
        quiz.save(update_fields=['title'])
        QuizQuestion.objects.create(
            quiz=quiz, question_text='Q1',
            option_a='A', option_b='B', option_c='C',
            correct_answer='a',
        )
        QuizQuestion.objects.create(
            quiz=quiz, question_text='Q2',
            option_a='A', option_b='B', option_c='C',
            correct_answer='b',
        )

        attempt = QuizAttempt.objects.create(
            user=user, quiz=quiz,
            answers=[
                {'question_id': 1, 'selected_answer': 'a', 'is_correct': True},
                {'question_id': 2, 'selected_answer': 'b', 'is_correct': True},
            ],
        )

        score = attempt.calculate_score()
        self.assertEqual(score, 100)
        self.assertTrue(attempt.passed)


class StoryQuizProvisioningTests(APITestCase):
    """Every published story must resolve to a playable quiz.

    The story reader's "Take Quiz" CTA looks a quiz up by story id, so a
    published story without one is a dead button that reports "Quiz coming
    soon" to the reader.
    """

    def setUp(self):
        self.author = User.objects.create_user(
            'author1',
            email='author1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.visitor = User.objects.create_user(
            'visitor2',
            email='visitor2@example.com',
            password='hunter2secure',
            role='visitor',
        )

    def _publish(self, title, **kwargs):
        return Story.objects.create(
            title=title,
            content=kwargs.pop('content', 'A tale from the highlands.'),
            author=self.author,
            status=Story.Status.PUBLISHED,
            **kwargs,
        )

    def test_publishing_a_story_creates_its_quiz(self):
        story = self._publish('The Talking Pot of Foumban')

        quiz = Quiz.objects.get(story=story)
        self.assertEqual(quiz.questions.count(), 4)
        self.assertEqual(quiz.passing_score, 70)

    def test_published_story_quiz_is_discoverable_through_the_api(self):
        story = self._publish('The Weaver Bird and the Lion')

        self.client.force_authenticate(self.visitor)
        response = self.client.get(
            reverse('gamification:quiz-list'),
            {'story': story.pk},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['story'], story.pk)

    def test_every_published_story_has_a_quiz(self):
        titles = [
            'The Sacred Forest of Foreke-Dschang',
            'The Bamileke Elephant Dance',
            'Bimbia: Where Memory Lives',
            'A Brand New Uncurated Story',
        ]
        for title in titles:
            self._publish(title)

        for story in Story.objects.filter(status=Story.Status.PUBLISHED):
            with self.subTest(story=story.title):
                quiz = Quiz.objects.filter(story=story).first()
                self.assertIsNotNone(quiz, f'"{story.title}" has no quiz at all')
                self.assertGreater(
                    quiz.questions.count(),
                    0,
                    f'"{story.title}" has a quiz with no questions',
                )

    def test_generated_answers_are_not_always_option_a(self):
        """A quiz whose answer is always "A" teaches readers to stop reading."""
        Story.objects.create(
            title='A Curated Anchor Story',
            content='Anchor content.',
            author=self.author,
            status=Story.Status.PUBLISHED,
        )
        for title in ('Curated Story One', 'Curated Story Two'):
            self._publish(title, region='Cameroon')

        letters = set()
        for quiz in Quiz.objects.all():
            letters.update(quiz.questions.values_list('correct_answer', flat=True))
        self.assertNotEqual(
            letters,
            {'a'},
            'every generated question put the correct answer in option A',
        )

    def test_generated_answers_are_letters_the_model_accepts(self):
        """`correct_answer` is max_length=1 with choices a-d.

        A generated question that stored the option *field* name instead of its
        letter would silently grade every answer wrong, and on PostgreSQL the
        over-long value would be rejected outright.
        """
        self._publish('A Story Needing A Generated Quiz', region='West Region')

        for question in QuizQuestion.objects.all():
            with self.subTest(question=question.question_text):
                self.assertIn(
                    question.correct_answer,
                    ('a', 'b', 'c', 'd'),
                    f'stored {question.correct_answer!r}, which is not an option letter',
                )

    def test_generated_options_are_distinct(self):
        """No question may offer the same option twice.

        A repeated distractor makes the question unanswerable by reasoning, and
        the collection can be any shape, so this is checked across the metadata
        combinations a real story arrives with.
        """
        shapes = {
            'bare': {},
            'region only': {'region': 'West Region'},
            'summary only': {'summary': 'A trader uncovers a family secret.'},
            'lesson only': {'moral_lesson': 'Patience outlasts haste.'},
            'context only': {'cultural_context': 'Foumban is a royal seat.'},
            'source only': {'source': 'Oral history from Bafoussam'},
            'language only': {'language': 'fr'},
            'fully described': {
                'region': 'Littoral',
                'summary': 'A trader uncovers a family secret.',
                'moral_lesson': 'Patience outlasts haste.',
                'cultural_context': 'A coastal trading tradition.',
                'source': 'Oral history from Kribi',
                'language': 'en',
            },
        }

        for index, (label, fields) in enumerate(shapes.items()):
            with self.subTest(shape=label):
                story = self._publish(f'Shape Probe {index} {label}', **fields)
                questions = story.quiz.questions.order_by('order')
                self.assertEqual(questions.count(), 4)
                for question in questions:
                    options = [
                        question.option_a,
                        question.option_b,
                        question.option_c,
                        question.option_d,
                    ]
                    options = [o for o in options if o]
                    self.assertEqual(
                        len(set(options)),
                        len(options),
                        f'"{question.question_text}" repeats an option: {options}',
                    )

    def test_generated_quiz_always_has_four_questions(self):
        """Even a story with no region, summary, lesson or source."""
        story = self._publish('A Bare Minimum Story')

        quiz = story.quiz
        self.assertEqual(quiz.questions.count(), 4)

    def test_quiz_is_not_duplicated_when_a_story_is_resaved(self):
        story = self._publish('The Moon and the Potter')

        story.cultural_context = 'Updated context for the revision.'
        story.save()

        self.assertEqual(Quiz.objects.filter(story=story).count(), 1)
        self.assertEqual(Quiz.objects.get(story=story).questions.count(), 4)

    def test_draft_story_does_not_get_a_quiz(self):
        story = Story.objects.create(
            title='An Unfinished Draft',
            content='Still being written.',
            author=self.author,
            status=Story.Status.DRAFT,
        )
        self.assertFalse(Quiz.objects.filter(story=story).exists())

    def test_backfill_repairs_a_quiz_with_no_questions(self):
        story = self._publish('A Story With An Empty Quiz')
        quiz = story.quiz
        quiz.questions.all().delete()
        self.assertEqual(quiz.questions.count(), 0)

        summary = ensure_quizzes_for_published_stories()

        self.assertEqual(summary['repaired'], 1)
        self.assertEqual(quiz.questions.count(), 4)

    def test_backfill_leaves_complete_quizzes_untouched(self):
        self._publish('A Story That Is Already Fine')

        summary = ensure_quizzes_for_published_stories()

        self.assertEqual(summary['unchanged'], 1)
        self.assertEqual(summary['questions_added'], 0)

    def test_reader_can_complete_an_auto_provisioned_quiz_end_to_end(self):
        """The whole journey for a story that never had a hand-written quiz.

        The reader finds the quiz through the story, starts an attempt, answers
        every question, and is graded — which is what "functional" has to mean
        for a story whose quiz was generated on publish.
        """
        story = self._publish('A Newly Published Story', region='West Region')
        self.client.force_authenticate(self.visitor)

        listing = self.client.get(
            reverse('gamification:quiz-list'),
            {'story': story.pk},
        )
        self.assertEqual(listing.status_code, status.HTTP_200_OK)
        self.assertEqual(listing.data['count'], 1)
        quiz_id = listing.data['results'][0]['id']

        detail = self.client.get(reverse('gamification:quiz-detail', args=[quiz_id]))
        self.assertEqual(len(detail.data['questions']), 4)
        # The API must not hand out the answers.
        for question in detail.data['questions']:
            self.assertNotIn('correct_answer', question)

        started = self.client.post(
            reverse('gamification:quiz-start', args=[quiz_id]),
        )
        self.assertEqual(started.status_code, status.HTTP_201_CREATED)

        for question in detail.data['questions']:
            # Answer correctly by reading the answer out of the database, the
            # way a reader who got it right would.
            correct = QuizQuestion.objects.get(pk=question['id']).correct_answer
            graded = self.client.post(
                reverse('gamification:quiz-submit-answer', args=[quiz_id]),
                {'question_id': question['id'], 'selected_answer': correct},
                format='json',
            )
            self.assertEqual(graded.status_code, status.HTTP_200_OK)
            self.assertTrue(graded.data['is_correct'])

        finished = self.client.post(
            reverse('gamification:quiz-finish', args=[quiz_id]),
        )
        self.assertEqual(finished.status_code, status.HTTP_200_OK)
        self.assertEqual(finished.data['score'], 100)
        self.assertTrue(finished.data['passed'])
        self.assertEqual(finished.data['xp_earned'], story.quiz.xp_reward)

        profile = self.client.get(reverse('gamification:user-profile'))
        self.assertEqual(profile.data['quizzes_passed'], 1)
        self.assertEqual(profile.data['total_xp'], story.quiz.xp_reward)

    def test_story_filter_ignores_a_non_numeric_story_id(self):
        self._publish('A Story With A Filter Test')
        self.client.force_authenticate(self.visitor)

        response = self.client.get(
            reverse('gamification:quiz-list'),
            {'story': 'not-a-number'},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 0)

    def test_story_filter_returns_only_the_requested_story(self):
        first = self._publish('The First Story Of Two')
        self._publish('The Second Story Of Two')
        self.client.force_authenticate(self.visitor)

        response = self.client.get(
            reverse('gamification:quiz-list'),
            {'story': first.pk},
        )

        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['story'], first.pk)


WAT = ZoneInfo('Africa/Douala')
UTC = ZoneInfo('UTC')


def at(year, month, day, hour=12, minute=0, tz=WAT):
    """An aware datetime in [tz], for driving the clock in a test."""
    return datetime(year, month, day, hour, minute, tzinfo=tz)


class StreakActivityTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'streaker', email='streaker@example.com', password='hunter2secure'
        )
        self.profile = UserProfile.objects.create(user=self.user)

    @patch('django.utils.timezone.now')
    def test_first_activity_starts_a_streak_at_one(self, now):
        now.return_value = at(2026, 3, 10)

        streaks.record_activity(self.user)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 1)
        self.assertEqual(self.profile.longest_streak, 1)
        self.assertEqual(self.profile.last_active_date, datetime(2026, 3, 10).date())

    @patch('django.utils.timezone.now')
    def test_second_activity_same_day_does_not_double_count(self, now):
        now.return_value = at(2026, 3, 10, 8)
        streaks.record_activity(self.user)
        now.return_value = at(2026, 3, 10, 23)
        streaks.record_activity(self.user)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 1)
        self.assertEqual(self.profile.longest_streak, 1)

    @patch('django.utils.timezone.now')
    def test_consecutive_day_extends_the_run(self, now):
        now.return_value = at(2026, 3, 10)
        streaks.record_activity(self.user)
        now.return_value = at(2026, 3, 11)
        streaks.record_activity(self.user)
        now.return_value = at(2026, 3, 12)
        streaks.record_activity(self.user)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 3)
        self.assertEqual(self.profile.longest_streak, 3)

    @patch('django.utils.timezone.now')
    def test_a_missed_day_restarts_at_one(self, now):
        now.return_value = at(2026, 3, 10)
        streaks.record_activity(self.user)
        now.return_value = at(2026, 3, 11)
        streaks.record_activity(self.user)
        # Two days later: the 11th was missed.
        now.return_value = at(2026, 3, 13)
        streaks.record_activity(self.user)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 1)
        # The old run is still the record.
        self.assertEqual(self.profile.longest_streak, 2)

    @patch('django.utils.timezone.now')
    def test_late_evening_read_lands_on_the_readers_own_day(self, now):
        """The bug this module exists for: UTC dated 23:30 in Cameroon to the
        previous day, breaking a streak the reader had actually kept."""
        now.return_value = at(2026, 3, 10, 23, 30, tz=WAT)
        streaks.record_activity(self.user)
        now.return_value = at(2026, 3, 11, 23, 30, tz=WAT)
        streaks.record_activity(self.user)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.last_active_date, datetime(2026, 3, 11).date())
        self.assertEqual(self.profile.current_streak, 2)

    @patch('django.utils.timezone.now')
    def test_same_instant_is_a_different_day_for_readers_in_different_zones(self, now):
        """00:30 on the 12th in UTC is already the 12th in Cameroon, but the
        11th in New York. Each reader's streak follows their own clock."""
        instant = at(2026, 3, 12, 0, 30, tz=UTC)

        now.return_value = instant
        douala = User.objects.create_user('douala', password='hunter2secure')
        douala_profile = UserProfile.objects.create(user=douala, timezone='Africa/Douala')

        now.return_value = instant
        new_york = User.objects.create_user('ny', password='hunter2secure')
        ny_profile = UserProfile.objects.create(
            user=new_york, timezone='America/New_York'
        )

        streaks.record_activity(douala)
        streaks.record_activity(new_york)

        douala_profile.refresh_from_db()
        ny_profile.refresh_from_db()
        self.assertEqual(
            douala_profile.last_active_date, datetime(2026, 3, 12).date()
        )
        self.assertEqual(
            ny_profile.last_active_date, datetime(2026, 3, 11).date()
        )

    @patch('django.utils.timezone.now')
    def test_unknown_timezone_falls_back_to_the_default_zone(self, now):
        now.return_value = at(2026, 3, 12, 0, 30, tz=UTC)
        streaks.record_activity(self.user, timezone_name='Mars/Olympus_Mons')

        self.profile.refresh_from_db()
        # Africa/Douala is UTC+1, so 00:30 UTC is 01:30 on the 12th there.
        self.assertEqual(self.profile.last_active_date, datetime(2026, 3, 12).date())
        self.assertEqual(self.profile.timezone, 'Africa/Douala')


class LiveStreakTests(TestCase):
    """A stored streak stops being true once a day is missed."""

    def setUp(self):
        self.user = User.objects.create_user(
            'lapsed', email='lapsed@example.com', password='hunter2secure'
        )
        self.today = datetime(2026, 3, 20).date()
        self.profile = UserProfile.objects.create(
            user=self.user,
            current_streak=5,
            longest_streak=9,
            last_active_date=self.today - timedelta(days=2),
        )

    def test_a_missed_yesterday_reports_no_live_streak(self):
        self.assertEqual(streaks.live_streak(self.profile, self.today), 0)

    def test_activity_yesterday_keeps_the_streak_live_today(self):
        self.profile.last_active_date = self.today - timedelta(days=1)
        self.assertEqual(streaks.live_streak(self.profile, self.today), 5)

    def test_activity_today_keeps_the_streak_live(self):
        self.profile.last_active_date = self.today
        self.assertEqual(streaks.live_streak(self.profile, self.today), 5)

    def test_the_stored_run_is_untouched_by_going_live_zero(self):
        streaks.live_streak(self.profile, self.today)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 5)
        self.assertEqual(self.profile.longest_streak, 9)

    def test_no_activity_ever_is_not_a_live_streak(self):
        self.profile.last_active_date = None
        self.assertEqual(streaks.live_streak(self.profile, self.today), 0)

    def test_active_today_reflects_the_readers_own_day(self):
        self.profile.last_active_date = self.today
        self.assertTrue(streaks.is_active_today(self.profile, self.today))
        self.profile.last_active_date = self.today - timedelta(days=1)
        self.assertFalse(streaks.is_active_today(self.profile, self.today))


class StreakAtRiskTests(TestCase):
    def setUp(self):
        self.today = datetime(2026, 3, 20).date()

    def _profile(self, username, streak, days_ago):
        user = User.objects.create_user(username, password='hunter2secure')
        return UserProfile.objects.create(
            user=user,
            current_streak=streak,
            last_active_date=self.today - timedelta(days=days_ago),
        )

    def test_at_risk_when_a_live_streak_has_no_activity_today(self):
        self.assertTrue(streaks.streak_at_risk(self._profile('a', 4, 1), self.today))

    def test_not_at_risk_once_active_today(self):
        self.assertFalse(streaks.streak_at_risk(self._profile('b', 4, 0), self.today))

    def test_not_at_risk_when_the_run_is_already_broken(self):
        self.assertFalse(streaks.streak_at_risk(self._profile('c', 4, 2), self.today))

    def test_not_at_risk_for_a_reader_with_no_streak(self):
        self.assertFalse(streaks.streak_at_risk(self._profile('d', 0, 1), self.today))

    @patch('django.utils.timezone.now')
    def test_only_outstanding_live_streaks_are_selected(self, now):
        now.return_value = at(2026, 3, 20, 9)
        self._profile('pending', 3, 1)
        self._profile('done', 3, 0)
        self._profile('broken', 3, 5)
        self._profile('none', 0, 1)

        selected = {
            profile.user.username for profile in streaks.users_at_risk_today()
        }
        self.assertEqual(selected, {'pending'})


class GrantXpAndStatsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'grader', email='grader@example.com', password='hunter2secure'
        )
        self.profile = UserProfile.objects.create(user=self.user)

    @patch('django.utils.timezone.now')
    def test_awarding_xp_also_advances_the_streak(self, now):
        now.return_value = at(2026, 4, 1, 10)

        streaks.grant_xp_and_stats(self.user, xp=90, quizzes_passed=1)

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.total_xp, 90)
        self.assertEqual(self.profile.quizzes_passed, 1)
        self.assertEqual(self.profile.total_quiz_xp, 90)
        self.assertEqual(self.profile.current_streak, 1)

    @patch('django.utils.timezone.now')
    def test_level_advances_when_xp_crosses_the_threshold(self, now):
        now.return_value = at(2026, 4, 1, 10)
        streaks.grant_xp_and_stats(self.user, xp=250, quizzes_passed=1)

        self.profile.refresh_from_db()
        # 250 XP at 100 XP per level is level 3.
        self.assertEqual(self.profile.level, 3)


class TimezonePersistenceTests(TestCase):
    """The stored zone must only ever be overwritten by a real IANA name.

    Flutter's `DateTime.timeZoneName` reports abbreviations such as ``WAT``, not
    IANA names, so an unguarded assignment would rewrite a correct stored zone
    to the default on every launch.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            'zonekeeper', email='zone@example.com', password='hunter2secure'
        )

    @patch('django.utils.timezone.now')
    def test_abbreviation_does_not_clobber_a_real_stored_zone(self, now):
        now.return_value = at(2026, 3, 12, 9)
        self.profile = UserProfile.objects.create(
            user=self.user,
            timezone='Europe/London',
            current_streak=4,
            last_active_date=datetime(2026, 3, 11).date(),
        )

        streaks.record_activity(self.user, timezone_name='WAT')

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.timezone, 'Europe/London')
        # The day still counts even though the zone name was useless.
        self.assertEqual(self.profile.current_streak, 5)
        self.assertEqual(self.profile.last_active_date, datetime(2026, 3, 12).date())

    @patch('django.utils.timezone.now')
    def test_blank_zone_does_not_clobber_a_stored_zone(self, now):
        now.return_value = at(2026, 3, 12, 9)
        self.profile = UserProfile.objects.create(
            user=self.user,
            timezone='Asia/Douala',
            current_streak=2,
            last_active_date=datetime(2026, 3, 11).date(),
        )

        streaks.record_activity(self.user, timezone_name='')

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.timezone, 'Asia/Douala')

    @patch('django.utils.timezone.now')
    def test_a_real_zone_is_persisted(self, now):
        now.return_value = at(2026, 3, 12, 9)
        self.profile = UserProfile.objects.create(
            user=self.user,
            timezone='Africa/Douala',
            current_streak=3,
            last_active_date=datetime(2026, 3, 11).date(),
        )

        streaks.record_activity(self.user, timezone_name='Europe/London')

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.timezone, 'Europe/London')

    @patch('django.utils.timezone.now')
    def test_garbage_zone_still_advances_the_streak(self, now):
        now.return_value = at(2026, 3, 12, 9)
        self.profile = UserProfile.objects.create(
            user=self.user,
            timezone='Europe/London',
            current_streak=1,
            last_active_date=datetime(2026, 3, 11).date(),
        )

        streaks.record_activity(self.user, timezone_name='GMT+1')

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.current_streak, 2)
        self.assertEqual(self.profile.last_active_date, datetime(2026, 3, 12).date())

    @patch('django.utils.timezone.now')
    def test_repeat_ping_with_a_bad_zone_keeps_the_good_zone(self, now):
        """The regression that matters: every launch must be safe.

        A real app pings on every start and resume, so a client that cannot name
        its zone must not erode a good stored zone one launch at a time.
        """
        now.return_value = at(2026, 3, 12, 9)
        self.profile = UserProfile.objects.create(
            user=self.user,
            timezone='Europe/London',
            current_streak=4,
            last_active_date=datetime(2026, 3, 11).date(),
        )

        for _ in range(3):
            streaks.record_activity(self.user, timezone_name='WAT')

        self.profile.refresh_from_db()
        self.assertEqual(self.profile.timezone, 'Europe/London')
        self.assertEqual(self.profile.current_streak, 5)
