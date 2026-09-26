"""
Tests for the server-rendered web interface.

Focus: the screens/actions added for parity with ARCHITECTURE.md and
FUNCTIONALITY_OUTLINE.md — story form (§2), profile (§1), audio/video
media UI (§6/§7), quizzes hub (§8) and the artifact audio guide (§5).
"""

from django.test import TestCase, override_settings
from django.urls import reverse
from django.template import Context, Template

from gamification.models import Badge, Quiz, QuizAttempt, QuizQuestion, UserProfile
from media_app.models import AudioNarrationJob, VideoGenerationJob
from stories.models import Story, StoryCategory
from users.models import User


@override_settings(MEDIA_URL='/media/')
class WebSmokeTestCase(TestCase):
    """Shared fixtures for the web parity screens."""

    @classmethod
    def setUpTestData(cls):
        cls.visitor = User.objects.create_user(
            username='web_visitor', password='testpass123', role='visitor',
        )
        cls.contributor = User.objects.create_user(
            username='web_contributor', password='testpass123', role='contributor',
        )
        cls.manager = User.objects.create_user(
            username='web_manager', password='testpass123', role='institution_manager',
        )
        cls.category = StoryCategory.objects.create(name='Folktales')
        cls.story = Story.objects.create(
            title='The Baobab and the Drum',
            content='Once upon a time **in the savannah**…',
            summary='A tale about rhythm and patience.',
            author=cls.contributor,
            status=Story.Status.PUBLISHED,
            region='Northwest',
        )
        cls.story.categories.add(cls.category)

    def setUp(self):
        self.client.defaults['HTTP_USER_AGENT'] = 'TestAgent/1.0'


class MarkdownRenderingTests(TestCase):
    def test_story_markdown_renders_as_html_instead_of_escaped_tags(self):
        template = Template('{% load web_extras %}{{ content|markdown }}')
        rendered = template.render(Context({
            'content': '# A Title\n\nA **bold** paragraph.',
        }))

        self.assertIn('<h1>A Title</h1>', rendered)
        self.assertIn('<p>A <strong>bold</strong> paragraph.</p>', rendered)
        self.assertNotIn('&lt;h1&gt;', rendered)


class StoryFormTests(WebSmokeTestCase):
    """Story create/edit — web mirror of the mobile StoryFormScreen."""

    def test_anonymous_is_redirected_to_login(self):
        response = self.client.get(reverse('web:story-new'))
        self.assertEqual(response.status_code, 302)
        self.assertIn('login', response.url)

    def test_visitor_cannot_access_form(self):
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:story-new'))
        self.assertEqual(response.status_code, 403)

    def test_contributor_gets_form(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-new'))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Save Draft')
        self.assertContains(response, 'Submit for Review')

    def test_contributor_can_create_draft(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.post(reverse('web:story-save'), {
            'title': 'Web Created Story',
            'content': 'Markdown **content** from the web form.',
            'summary': 'Created in a test.',
            'language': 'en',
            'status': 'draft',
            'categories': [str(self.category.id)],
        })
        story = Story.objects.get(slug='web-created-story')
        self.assertEqual(story.status, Story.Status.DRAFT)
        self.assertEqual(story.author, self.contributor)
        self.assertRedirects(
            response, reverse('web:story-detail', args=[story.slug]),
        )

    def test_contributor_can_submit_for_review(self):
        self.client.login(username='web_contributor', password='testpass123')
        self.client.post(reverse('web:story-save'), {
            'title': 'Pending Story',
            'content': 'Content here.',
            'status': 'pending',
        })
        story = Story.objects.get(slug='pending-story')
        self.assertEqual(story.status, Story.Status.PENDING)

    def test_owner_can_edit_and_manager_override(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-edit', args=[self.story.slug]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.story.title)

        # A different contributor may not edit someone else's story.
        other = User.objects.create_user(
            username='web_other', password='testpass123', role='contributor',
        )
        self.client.login(username='web_other', password='testpass123')
        response = self.client.get(reverse('web:story-edit', args=[self.story.slug]))
        self.assertEqual(response.status_code, 403)

        # Managers override ownership (matches IsStoryOwnerOrReadOnly).
        self.client.login(username='web_manager', password='testpass123')
        response = self.client.get(reverse('web:story-edit', args=[self.story.slug]))
        self.assertEqual(response.status_code, 200)

    def test_story_detail_shows_edit_link_for_owner(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, reverse('web:story-edit', args=[self.story.slug]))


class ProfileTests(WebSmokeTestCase):
    """Profile screen — web mirror of the mobile ProfileScreen."""

    def test_requires_login(self):
        response = self.client.get(reverse('web:profile'))
        self.assertEqual(response.status_code, 302)

    def test_profile_renders_role_badge(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:profile'))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Contributor')

    def test_profile_update_saves_names(self):
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.post(reverse('web:profile-update'), {
            'first_name': 'Amina',
            'last_name': 'Nkeng',
            'email': 'web_visitor@example.com',
        }, follow=True)
        self.visitor.refresh_from_db()
        self.assertEqual(self.visitor.first_name, 'Amina')
        self.assertContains(response, 'Profile updated.')

    def test_profile_delete_removes_account(self):
        self.client.login(username='web_visitor', password='testpass123')
        self.client.post(reverse('web:profile-delete'))
        self.assertFalse(User.objects.filter(pk=self.visitor.pk).exists())


class StoryMediaTests(WebSmokeTestCase):
    """Audio narration + AI video UI (§6 / §7) on story detail."""

    def test_owner_sees_generate_narration_prompt(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Generate narration')
        self.assertContains(response, 'Generate video')

    def test_visitor_sees_no_media_panel(self):
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertNotContains(response, 'Generate narration')

    def test_completed_narration_renders_audio_player(self):
        AudioNarrationJob.objects.create(
            user=self.contributor,
            story=self.story,
            language='en',
            status=AudioNarrationJob.Status.COMPLETED,
            duration=42,
        )
        # Narrations only surface for signed-in users (matches the view).
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertContains(response, 'audio-toggle')

    def test_processing_video_job_shows_poller(self):
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='test prompt',
            luma_job_id='luma_123',
        )
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertContains(response, 'data-video-poll')

        # Status polling endpoint reflects the pending job.
        response = self.client.get(
            reverse('web:story-video-status', args=[self.story.slug])
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['status'], VideoGenerationJob.Status.PROCESSING)
        job.refresh_from_db()
        self.assertEqual(job.status, VideoGenerationJob.Status.PROCESSING)

    def test_video_generation_requires_ownership(self):
        User.objects.create_user(
            username='web_writer2', password='testpass123', role='contributor',
        )
        self.client.login(username='web_writer2', password='testpass123')
        response = self.client.post(
            reverse('web:story-generate-video', args=[self.story.slug]), {}
        )
        self.assertEqual(response.status_code, 403)


class QuizzesHubTests(WebSmokeTestCase):
    """Quizzes hub — mirrors the mobile quiz entry points (§8)."""

    def setUp(self):
        super().setUp()
        self.quiz = Quiz.objects.create(story=self.story, passing_score=70)
        QuizQuestion.objects.create(
            quiz=self.quiz,
            question_text='What does the baobab symbolise?',
            option_a='Endurance', option_b='Speed', option_c='Wealth', option_d='Silence',
            correct_answer='a',
        )

    def test_hub_lists_visible_quiz(self):
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:quizzes'))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.story.title)

    def test_hub_hides_quizzes_for_unpublished_stories(self):
        self.story.status = Story.Status.DRAFT
        self.story.save()
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:quizzes'))
        self.assertNotContains(response, self.story.title)
        self.story.status = Story.Status.PUBLISHED
        self.story.save()

    def test_hub_shows_latest_attempt(self):
        attempt = QuizAttempt.objects.create(
            user=self.visitor, quiz=self.quiz, total_questions=1,
        )
        attempt.calculate_score()
        attempt.status = QuizAttempt.Status.COMPLETED
        attempt.save()
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:quizzes'))
        self.assertContains(response, 'Last try')

    def test_gamification_links_to_hub(self):
        self.client.login(username='web_visitor', password='testpass123')
        UserProfile.objects.create(user=self.visitor)
        Badge.objects.create(
            name='First Steps', slug='first-steps', description='Read your first story.',
        )
        response = self.client.get(reverse('web:gamification'))
        self.assertContains(response, reverse('web:quizzes'))

    def test_story_shows_quiz_to_anonymous_visitors(self):
        response = self.client.get(reverse('web:story-detail', args=[self.story.slug]))
        self.assertContains(response, 'Sign in to take quiz')
        self.assertContains(response, reverse('web:quiz-play', args=[self.quiz.id]))

    def test_web_quiz_can_start_answer_and_finish(self):
        self.client.login(username='web_visitor', password='testpass123')
        quiz_url = reverse('web:quiz-play', args=[self.quiz.id])

        response = self.client.post(reverse('web:quiz-start', args=[self.quiz.id]))
        self.assertRedirects(response, quiz_url)
        response = self.client.get(quiz_url)
        self.assertContains(response, self.quiz.questions.first().question_text)

        question = self.quiz.questions.first()
        response = self.client.post(
            reverse('web:quiz-answer', args=[self.quiz.id, question.id]),
            {'answer': question.correct_answer},
        )
        self.assertRedirects(response, quiz_url)

        response = self.client.post(reverse('web:quiz-finish', args=[self.quiz.id]))
        self.assertRedirects(response, quiz_url)
        attempt = QuizAttempt.objects.get(user=self.visitor, quiz=self.quiz)
        self.assertEqual(attempt.status, QuizAttempt.Status.COMPLETED)
        self.assertEqual(attempt.score, 100)


class ArtifactAudioGuideTests(WebSmokeTestCase):
    """Artifact audio guide (§5 + §6) — render + generation action."""

    def _make_artifact(self, published=True):
        from qr_codes.models import Artifact

        return Artifact.objects.create(
            title=f'Test Artifact {self.id()}',
            category='instrument',
            is_published=published,
            created_by=self.manager,
        )

    def test_narration_renders_on_artifact_page(self):
        artifact = self._make_artifact()
        AudioNarrationJob.objects.create(
            user=self.manager, artifact=artifact, language='en',
            status=AudioNarrationJob.Status.COMPLETED,
        )
        response = self.client.get(reverse('web:artifact-detail', args=[artifact.slug]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Audio guide')

    def test_generation_prompt_shows_for_authenticated_users(self):
        artifact = self._make_artifact()
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:artifact-detail', args=[artifact.slug]))
        self.assertContains(response, 'Generate audio guide')

    def test_generation_prompt_hidden_from_anonymous(self):
        artifact = self._make_artifact()
        response = self.client.get(reverse('web:artifact-detail', args=[artifact.slug]))
        self.assertNotContains(response, 'Generate audio guide')

    def test_manager_can_generate_audio_guide(self):
        artifact = self._make_artifact()
        artifact.description = 'A royal drum from the Bamoun kingdom.'
        artifact.save()
        self.client.login(username='web_manager', password='testpass123')
        response = self.client.post(
            reverse('web:artifact-generate-audio', args=[artifact.slug]),
            {'language': 'en'},
            follow=True,
        )
        job = AudioNarrationJob.objects.filter(artifact=artifact).latest('id')
        self.assertEqual(job.status, AudioNarrationJob.Status.COMPLETED)
        self.assertContains(response, 'press play to listen')

    def test_existing_guide_is_reused_not_duplicated(self):
        artifact = self._make_artifact()
        artifact.description = 'A royal drum.'
        artifact.save()
        self.client.login(username='web_manager', password='testpass123')
        self.client.post(
            reverse('web:artifact-generate-audio', args=[artifact.slug]),
            {'language': 'en'},
        )
        # Second call must not create another job.
        self.client.post(
            reverse('web:artifact-generate-audio', args=[artifact.slug]),
            {'language': 'en'},
        )
        self.assertEqual(
            AudioNarrationJob.objects.filter(
                artifact=artifact, status=AudioNarrationJob.Status.COMPLETED,
            ).count(),
            1,
        )

    def test_unpublished_artifact_requires_manager(self):
        artifact = self._make_artifact(published=False)
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.post(
            reverse('web:artifact-generate-audio', args=[artifact.slug]),
            {'language': 'en'},
        )
        self.assertEqual(response.status_code, 403)


class WebRegisterUserTests(TestCase):
    """`web.services.register_user` shares `auth_user` with the API.

    Email now carries a case-insensitive unique constraint, so the duplicate
    check in the service is only a fast path. A racing insert must surface the
    same friendly error rather than an unhandled IntegrityError (500).
    """

    def test_creates_a_user(self):
        from web.services import register_user

        user, errors = register_user(
            username='newname',
            email='New@Example.com',
            password='hunter2secure',
            password2='hunter2secure',
            role='visitor',
        )

        self.assertEqual(errors, [])
        self.assertIsNotNone(user)
        self.assertEqual(user.email, 'new@example.com')

    def test_duplicate_email_is_rejected(self):
        from web.services import register_user

        User.objects.create_user('first', email='taken@example.com', password='hunter2secure')

        user, errors = register_user(
            username='second',
            email='TAKEN@example.com',
            password='hunter2secure',
            password2='hunter2secure',
            role='visitor',
        )

        self.assertIsNone(user)
        self.assertIn('A user with this email already exists.', errors)
