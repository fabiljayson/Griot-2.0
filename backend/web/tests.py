"""
Tests for the server-rendered web interface.

Focus: the screens/actions added for parity with ARCHITECTURE.md and
FUNCTIONALITY_OUTLINE.md — story form (§2), profile (§1), audio/video
media UI (§6/§7), quizzes hub (§8) and the artifact audio guide (§5).
"""

from django.template import Context, Template
from django.test import TestCase, override_settings
from django.urls import reverse

from gamification.models import Badge, QuizAttempt, QuizQuestion, UserProfile
from media_app.models import AudioNarrationJob, VideoGenerationJob
from stories.models import Story, StoryCategory, StoryFlag
from users.models import User

from .services import admin_dashboard_data


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
        User.objects.create_user(
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

    def test_multiline_template_notes_are_not_rendered(self):
        AudioNarrationJob.objects.create(
            user=self.contributor,
            story=self.story,
            language='en',
            status=AudioNarrationJob.Status.COMPLETED,
            duration=42,
        )
        self.client.login(username='web_contributor', password='testpass123')

        detail = self.client.get(
            reverse('web:story-detail', args=[self.story.slug]),
        )
        self.assertNotContains(detail, 'Names the engine rather than saying')
        self.assertNotContains(detail, 'Consent is stated plainly')

        stories = self.client.get(reverse('web:stories'))
        self.assertNotContains(stories, 'On the card, not only on the detail page')

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
        # Publishing a story auto-provisions its quiz, so reuse that one and
        # swap in the question this test needs.
        self.quiz = self.story.quiz
        self.quiz.questions.all().delete()
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

    def test_artifact_page_shows_the_short_visual_description(self):
        artifact = self._make_artifact()
        artifact.description = 'A carved wooden mask with copper details.'
        artifact.story = 'The long account of the mask and its cultural use.'
        artifact.save()

        response = self.client.get(
            reverse('web:artifact-detail', args=[artifact.slug]),
        )

        self.assertContains(response, 'A carved wooden mask with copper details.')
        self.assertNotContains(response, 'The long account of the mask')

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
        # F-03: rejected with a generic message that does not reveal *which*
        # field collided, so the form cannot be used to probe for accounts.
        # (The message may still mention both field names — what matters is
        # that it does not single one of them out as the colliding one.)
        self.assertTrue(any('already exists' in e for e in errors))
        self.assertFalse(any('That username is taken' in e for e in errors))
        self.assertFalse(any('email already exists' in e for e in errors))


class StoryProvenanceWebTests(WebSmokeTestCase):
    """Reader-facing story pages show location without provenance detail."""

    def test_story_detail_shows_region_without_provenance_details(self):
        self.story.region = 'Northwest'
        self.story.origin = Story.Origin.SEEDED
        self.story.licence = Story.Licence.CC_BY_NC
        self.story.rights_holder = 'The Kom kingdom'
        self.story.provenance_notes = 'Recorded with the elders of Foumban in 2021.'
        self.story.source = 'Discover Cameroon'
        self.story.save()

        response = self.client.get(
            reverse('web:story-detail', args=[self.story.slug])
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Northwest')
        self.assertNotContains(response, 'Demonstration content')
        self.assertNotContains(response, 'CC BY-NC 4.0')
        self.assertNotContains(response, 'The Kom kingdom')
        self.assertNotContains(response, 'Recorded with the elders of Foumban')
        self.assertNotContains(response, 'Discover Cameroon')
        self.assertNotContains(response, 'not yet recorded consent')

    def test_story_grid_keeps_region_without_seed_badge(self):
        self.story.origin = Story.Origin.SEEDED
        self.story.save()

        listing = self.client.get(reverse('web:stories'))
        self.assertContains(listing, self.story.region)
        self.assertNotContains(listing, 'Demonstration content')

    def test_withheld_consent_details_are_not_shown_on_the_detail_page(self):
        Story.objects.filter(pk=self.story.pk).update(
            consent_status=Story.Consent.WITHHELD,
        )
        response = self.client.get(
            reverse('web:story-detail', args=[self.story.slug])
        )
        self.assertNotContains(response, 'Consent withheld')

    def test_unverified_consent_details_are_not_shown(self):
        response = self.client.get(
            reverse('web:story-detail', args=[self.story.slug])
        )
        self.assertNotContains(response, 'not yet recorded consent')

    def test_narration_credit_names_the_engine(self):
        self.client.login(username='web_contributor', password='testpass123')
        AudioNarrationJob.objects.create(
            user=self.contributor,
            story=self.story,
            narration_text='Once upon a time…',
            status=AudioNarrationJob.Status.COMPLETED,
            audio_url='/media/narration.mp3',
            engine='gtts',
        )
        response = self.client.get(
            reverse('web:story-detail', args=[self.story.slug])
        )
        self.assertContains(response, 'AI-generated narration (gtts)')

    def test_form_offers_provenance_fields(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-new'))
        self.assertContains(response, 'name="origin"')
        self.assertContains(response, 'name="licence"')
        self.assertContains(response, 'name="rights_holder"')
        self.assertContains(response, 'name="provenance_notes"')
        self.assertContains(response, 'name="recorded_at"')

    def test_form_has_no_consent_field_to_self_declare(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.get(reverse('web:story-new'))
        self.assertNotContains(response, 'name="consent_status"')

    def test_contributor_can_declare_provenance_from_the_form(self):
        self.client.login(username='web_contributor', password='testpass123')
        self.client.post(reverse('web:story-save'), {
            'title': 'Sourced Story',
            'content': 'Content here.',
            'status': 'draft',
            'origin': Story.Origin.ORAL_TRANSCRIPTION,
            'licence': Story.Licence.CC_BY_SA,
            'rights_holder': 'The Bamoun council of elders',
            'provenance_notes': 'Transcribed from a Mafa telling.',
            'recorded_at': '2024-05-17',
        })
        story = Story.objects.get(slug='sourced-story')
        self.assertEqual(story.origin, Story.Origin.ORAL_TRANSCRIPTION)
        self.assertEqual(story.licence, Story.Licence.CC_BY_SA)
        self.assertEqual(story.rights_holder, 'The Bamoun council of elders')
        self.assertEqual(story.recorded_at.isoformat(), '2024-05-17')

    def test_a_garbage_date_does_not_break_the_save(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.post(reverse('web:story-save'), {
            'title': 'Odd Date Story',
            'content': 'Content here.',
            'status': 'draft',
            'recorded_at': 'not-a-date',
        })
        self.assertEqual(response.status_code, 302)
        story = Story.objects.get(slug='odd-date-story')
        self.assertIsNone(story.recorded_at)

    def test_an_unknown_origin_choice_falls_back_rather_than_erroring(self):
        self.client.login(username='web_contributor', password='testpass123')
        response = self.client.post(reverse('web:story-save'), {
            'title': 'Bad Choice Story',
            'content': 'Content here.',
            'status': 'draft',
            'origin': 'invented-origin',
            'licence': 'invented-licence',
        })
        self.assertEqual(response.status_code, 302)
        story = Story.objects.get(slug='bad-choice-story')
        self.assertEqual(story.origin, Story.Origin.UNKNOWN)
        self.assertEqual(story.licence, Story.Licence.UNDETERMINED)

    def test_bulk_publish_action_skips_stories_with_withheld_consent(self):
        """A bulk UPDATE would step past the model's consent guard."""
        from django.contrib import messages
        from django.contrib.admin.sites import AdminSite
        from django.contrib.messages.storage.fallback import FallbackStorage
        from django.test import RequestFactory

        from stories.admin import StoryAdmin

        withheld = Story.objects.create(
            title='Withheld Story',
            content='Content.',
            author=self.contributor,
            status=Story.Status.DRAFT,
            consent_status=Story.Consent.WITHHELD,
        )
        allowed = Story.objects.create(
            title='Allowed Story',
            content='Content.',
            author=self.contributor,
            status=Story.Status.DRAFT,
        )

        request = RequestFactory().post('/admin/stories/story/')
        request.session = {}
        request._messages = FallbackStorage(request)
        request.user = self.manager

        admin_instance = StoryAdmin(Story, AdminSite())
        admin_instance.publish_stories(
            request, Story.objects.filter(pk__in=[withheld.pk, allowed.pk]),
        )

        stored = [str(m) for m in messages.get_messages(request)]
        self.assertTrue(
            any('consent is withheld' in line for line in stored),
            f'the moderator must be told what was skipped, got: {stored}',
        )

        withheld.refresh_from_db()
        allowed.refresh_from_db()
        self.assertEqual(withheld.status, Story.Status.DRAFT)
        self.assertEqual(allowed.status, Story.Status.PUBLISHED)
        self.assertIsNotNone(allowed.published_at)


class AdminModerationQueueTests(WebSmokeTestCase):
    """The dashboard's moderation queue — the one page an admin opens to work.

    It renders only when flags exist, and the development database had none, so
    this path had never executed against real data: a template error or a
    missing select_related would have surfaced only after the first reader
    reported a story.
    """

    def _flag(self, story, user, reason=StoryFlag.Reason.CULTURAL_INACCURACY):
        return StoryFlag.objects.create(story=story, user=user, reason=reason)

    def test_the_queue_renders_flags_when_they_exist(self):
        self._flag(self.story, self.visitor)
        self.client.login(username='web_manager', password='testpass123')

        response = self.client.get(reverse('web:admin-dashboard'))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.story.title)
        self.assertContains(response, '1 flag')

    def test_several_flags_on_one_story_are_grouped_under_it(self):
        second = User.objects.create_user(
            username='web_flagger', password='testpass123', role='visitor',
        )
        self._flag(self.story, self.visitor)
        self._flag(self.story, second, reason='cultural_inaccuracy')
        self.client.login(username='web_manager', password='testpass123')

        response = self.client.get(reverse('web:admin-dashboard'))

        self.assertContains(response, '2 flags')
        # One entry for the story, not one per flag.
        self.assertEqual(
            admin_dashboard_data()['moderation_queue'][0]['story'], self.story,
        )

    def test_a_resolved_flag_leaves_the_queue(self):
        flag = self._flag(self.story, self.visitor)
        self.client.login(username='web_manager', password='testpass123')
        self.assertEqual(len(admin_dashboard_data()['moderation_queue']), 1)

        flag.resolved = True
        flag.save()

        self.assertEqual(len(admin_dashboard_data()['moderation_queue']), 0)

    def test_an_empty_queue_renders_without_error(self):
        self.client.login(username='web_manager', password='testpass123')
        response = self.client.get(reverse('web:admin-dashboard'))
        self.assertEqual(response.status_code, 200)

    def test_the_queue_does_not_add_queries_per_story(self):
        """It must stay `select_related`, or it is an N+1 waiting for volume."""
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        for index in range(5):
            story = Story.objects.create(
                title=f'Flagged {index}', content='Content.',
                author=self.contributor, status=Story.Status.PUBLISHED,
            )
            self._flag(story, self.visitor)

        admin_dashboard_data()  # warm
        with CaptureQueriesContext(connection) as ctx:
            admin_dashboard_data()

        self.assertLessEqual(
            len(ctx.captured_queries), 60,
            f'queue pushed the dashboard to {len(ctx.captured_queries)} queries',
        )

    def test_a_visitor_cannot_see_the_dashboard(self):
        self._flag(self.story, self.visitor)
        self.client.login(username='web_visitor', password='testpass123')
        response = self.client.get(reverse('web:admin-dashboard'))
        self.assertEqual(response.status_code, 403)
