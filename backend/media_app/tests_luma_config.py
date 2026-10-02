"""A production server with no LUMA_API_KEY must fail, not fake success.

`MockLumaAIService` exists so the job lifecycle (pending -> processing ->
completed) can be exercised without paying for generations. It reports
`completed` and sets `video_url` to a `https://storage.example.com/...`
placeholder that plays nothing.

That is harmless on a laptop and actively harmful in production. With the key
unset, a deployed server would:

* mark the job COMPLETED, so the dashboard and the API both report success;
* spend the caller's `VIDEO_GENERATIONS_PER_USER_PER_DAY` quota on nothing;
* hand the user a player pointed at an unplayable placeholder, with no error
  anywhere to explain why the video does not load.

Nothing in the original code distinguished "no key because we are developing"
from "no key because nobody set it on the server", so the paid feature failed
silently. `get_luma_service()` now raises `LumaAIError` unless the mock is
explicitly allowed (`LUMA_ALLOW_MOCK`, defaulted to `DEBUG`).

These tests pin that gate and the three call sites that have to honour it.
"""

from unittest import mock

from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from media_app.models import VideoGenerationJob
from media_app.services import luma_ai
from media_app.services.luma_ai import LumaAIError, get_luma_service
from stories.models import Story
from users.models import User
from web.services import generate_story_video, refresh_video_job


class _ResetMemoisedService:
    """`get_luma_service` memoises into a module global.

    That is correct in production — it is built once per process — and wrong
    for tests: whichever test first calls it decides the service for every
    later test in the run, no matter what `override_settings` says. The suite
    runs in alphabetical order, so `media_app.tests` reaches the factory under
    `LUMA_ALLOW_MOCK = True` (set in `config.settings.test`) and leaves a
    `MockLumaAIService` cached for everything after it.

    Clear it before *and* after each test here, so these tests neither inherit
    a stale answer nor hand one to the tests that follow.
    """

    def setUp(self):
        super().setUp()
        luma_ai._service_instance = None
        self.addCleanup(setattr, luma_ai, '_service_instance', None)


class LumaServiceResolutionTests(_ResetMemoisedService, SimpleTestCase):
    """The factory's decision about which service to hand back."""

    @override_settings(LUMA_API_KEY='live-key', LUMA_ALLOW_MOCK=False)
    def test_a_key_always_wins(self):
        service = get_luma_service()
        self.assertIsInstance(service, luma_ai.LiveLumaAIService)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_no_key_and_no_opt_in_raises_rather_than_serving_the_mock(self):
        with self.assertRaises(LumaAIError) as ctx:
            get_luma_service()
        self.assertIn('LUMA_API_KEY', str(ctx.exception))

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=True)
    def test_no_key_but_explicit_opt_in_still_serves_the_mock(self):
        # A staging deploy that wants fake data opts in deliberately; local dev
        # gets this for free because DEBUG is true.
        self.assertIsInstance(get_luma_service(), luma_ai.MockLumaAIService)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_the_failure_is_not_memoised(self):
        # A failed lookup must not poison later calls: once an operator sets
        # the key and the process re-reads settings, resolution has to succeed
        # without a restart having quietly cached the error.
        with self.assertRaises(LumaAIError):
            get_luma_service()
        with override_settings(LUMA_API_KEY='late-key', LUMA_ALLOW_MOCK=False):
            self.assertIsInstance(get_luma_service(), luma_ai.LiveLumaAIService)


class LumaAPIViewTests(_ResetMemoisedService, TestCase):
    """`POST /api/videos/` must not report success for an unconfigured server."""

    def setUp(self):
        # Chain to the mixin: these classes define their own setUp, and
        # forgetting super() here is exactly how the memoised service leaks
        # back in from an earlier test module.
        super().setUp()
        self.contributor = User.objects.create_user(
            'luma-gate', email='luma-gate@example.com', password='hunter2secure',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for video generation.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.client = APIClient()
        self.client.force_authenticate(self.contributor)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_create_returns_an_error_status_not_a_completed_job(self):
        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': self.story.id,
            'prompt': 'a mask',
        }, format='json')

        # 502 is what the view already returns for other upstream failures.
        # The point is that it is an error at all, and never a 201 carrying a
        # job the client will poll forever.
        self.assertEqual(resp.status_code, 502, resp.data)
        self.assertNotIn('video_url', resp.data)

        # The job row exists, so it has to say why it died rather than sit
        # PENDING forever.
        job = VideoGenerationJob.objects.get()
        self.assertEqual(job.status, VideoGenerationJob.Status.FAILED)
        self.assertIn('LUMA_API_KEY', job.error_message)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_status_poll_does_not_error_when_luma_is_unconfigured(self):
        # The client loops on the status endpoint. A server that has lost its
        # key must answer with the stored state, not a 500 that the client
        # reads as a dead job.
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='a mask',
            luma_job_id='luma_existing',
            status=VideoGenerationJob.Status.PROCESSING,
            progress_percent=40,
        )

        url = reverse('media:video-generation-status', kwargs={'pk': job.id})
        resp = self.client.get(url)

        self.assertEqual(resp.status_code, 200, resp.data)
        job.refresh_from_db()
        self.assertEqual(job.status, VideoGenerationJob.Status.PROCESSING)
        self.assertEqual(job.progress_percent, 40)
        self.assertFalse(job.video_url)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_cancel_still_succeeds_locally_when_luma_is_unconfigured(self):
        # The user's intent to cancel has to be honoured even with no upstream
        # to cancel against; erroring here would leave a job the user was told
        # they had stopped.
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='a mask',
            luma_job_id='luma_existing',
            status=VideoGenerationJob.Status.PROCESSING,
        )

        url = reverse('media:video-generation-cancel', kwargs={'pk': job.id})
        resp = self.client.post(url)

        self.assertEqual(resp.status_code, 200, resp.data)
        job.refresh_from_db()
        self.assertEqual(job.status, VideoGenerationJob.Status.FAILED)
        self.assertEqual(job.error_message, 'Cancelled by user')


class LumaWebServiceTests(_ResetMemoisedService, TestCase):
    """The server-rendered path must report the same honest outcome."""

    def setUp(self):
        super().setUp()
        self.contributor = User.objects.create_user(
            'luma-web', email='luma-web@example.com', password='hunter2secure',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for video generation.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_generate_returns_an_error_message_not_a_success_one(self):
        message, level = generate_story_video(self.contributor, self.story, 'a mask')

        self.assertEqual(level, 'error')
        self.assertIn('unavailable', message)
        self.assertNotIn('check back shortly', message)

    @override_settings(LUMA_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_refresh_leaves_the_job_alone_rather_than_raising(self):
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='a mask',
            luma_job_id='luma_existing',
            status=VideoGenerationJob.Status.PROCESSING,
            progress_percent=40,
        )

        returned = refresh_video_job(self.contributor, self.story)

        self.assertEqual(returned, job)
        job.refresh_from_db()
        self.assertEqual(job.progress_percent, 40)
        self.assertFalse(job.video_url)
