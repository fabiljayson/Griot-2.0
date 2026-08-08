from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from stories.models import Story

from .models import Badge, Quiz, QuizAttempt, QuizQuestion, UserBadge, UserProfile

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
        self.story = Story.objects.create(
            title='The Wise Spider',
            content='A story about a clever spider.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
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
        quiz = Quiz.objects.create(story=story, title='Q')
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
