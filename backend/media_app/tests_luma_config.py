"""A server with no video provider configured must fail, not fake success.

`MockVideoProvider` exists so the job lifecycle (pending -> processing ->
completed) can be exercised without paying for generations. It reports
`completed` and sets `video_url` to a `https://storage.example.com/...`
placeholder that plays nothing.

That is harmless on a laptop and actively harmful in production. With no key
set, a deployed server would:

* mark the job COMPLETED, so the dashboard and the API both report success;
* spend the caller's `VIDEO_GENERATIONS_PER_USER_PER_DAY` quota on nothing;
* hand the user a player pointed at an unplayable placeholder, with no error
  anywhere to explain why the video does not load.

So the gate is explicit rather than inferred: `get_luma_service()` raises
`LumaAIError` unless the mock is permitted. Two switches control that, and
these tests pin both:

* `LUMA_ALLOW_MOCK` — the original opt-in for serving the mock at all when no
  key is configured (defaults to `DEBUG`).
* `VIDEO_ALLOW_MOCK_FALLBACK` — the newer, broader one: may the mock stand in
  when *every* live provider is out of credits or unconfigured? Defaults on,
  so a spent balance answers rather than 502s; setting it to 0 restores the
  strict behaviour asserted throughout this module.

The tests below set both off to exercise the strict path. The permissive
default is covered by `MockFallbackTests` at the bottom.
"""

from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from media_app.models import VideoGenerationJob
from media_app.services.luma_ai import LumaAIError, get_luma_service
from media_app.services.video_providers import reset_video_service
from stories.models import Story
from users.models import User
from web.services import generate_story_video, refresh_video_job

#: The mock half, for tests that configure a real key alongside it.
_MOCK_DISABLED = {
    'FAL_API_KEY': '',
    'LUMA_ALLOW_MOCK': False,
    'VIDEO_ALLOW_MOCK_FALLBACK': False,
}

#: Everything off: no keys, no mock. Every strict test below layers its own
#: `LUMA_API_KEY` on top of this, so the intent of each case reads in one place.
_NO_PROVIDERS = {
    'LUMA_API_KEY': '',
    **_MOCK_DISABLED,
}


def _live_keys(service):
    """Provider keys the chain would actually try, in order."""
    return [provider.key for provider in service.providers]


class _ResetMemoisedService:
    """`get_luma_service` memoises into a module global.

    That is correct in production — it is built once per process — and wrong
    for tests: whichever test first calls it decides the service for every
    later test in the run, no matter what `override_settings` says. The suite
    runs in alphabetical order, so `media_app.tests` reaches the factory under
    `LUMA_ALLOW_MOCK = True` (set in `config.settings.test`) and leaves a
    chain cached for everything after it.

    Clear it before *and* after each test here, so these tests neither inherit
    a stale answer nor hand one to the tests that follow.
    """

    def setUp(self):
        super().setUp()
        reset_video_service()
        self.addCleanup(reset_video_service)


class LumaServiceResolutionTests(_ResetMemoisedService, SimpleTestCase):
    """The factory's decision about which providers to hand back."""

    @override_settings(LUMA_API_KEY='live-key', **_MOCK_DISABLED)
    def test_a_key_always_wins(self):
        service = get_luma_service()
        self.assertEqual(_live_keys(service), ['luma'])
        self.assertIsNone(service.mock)
        self.assertEqual(service.providers[0].api_key, 'live-key')

    @override_settings(**_NO_PROVIDERS)
    def test_no_key_and_no_opt_in_raises_rather_than_serving_the_mock(self):
        with self.assertRaises(LumaAIError) as ctx:
            get_luma_service()
        self.assertIn('LUMA_API_KEY', str(ctx.exception))

    @override_settings(
        LUMA_API_KEY='', FAL_API_KEY='', LUMA_ALLOW_MOCK=True,
        VIDEO_ALLOW_MOCK_FALLBACK=False,
    )
    def test_no_key_but_explicit_opt_in_still_serves_the_mock(self):
        # A staging deploy that wants fake data opts in deliberately; local dev
        # gets this for free because DEBUG is true.
        service = get_luma_service()
        self.assertEqual(_live_keys(service), [])
        self.assertIsNotNone(service.mock)
        self.assertEqual(service.mock.key, 'mock')

    @override_settings(**_NO_PROVIDERS)
    def test_the_failure_is_not_memoised(self):
        # A failed lookup must not poison later calls: once an operator sets
        # the key and the process re-reads settings, resolution has to succeed
        # without a restart having quietly cached the error.
        with self.assertRaises(LumaAIError):
            get_luma_service()
        with override_settings(LUMA_API_KEY='late-key', **_MOCK_DISABLED):
            self.assertEqual(_live_keys(get_luma_service()), ['luma'])

    @override_settings(
        LUMA_API_KEY='live-key',
        FAL_API_KEY='fal-key',
        LUMA_ALLOW_MOCK=False,
        VIDEO_ALLOW_MOCK_FALLBACK=True,
    )
    def test_both_keys_build_both_providers_in_configured_order(self):
        service = get_luma_service()
        self.assertEqual(_live_keys(service), ['luma', 'fal'])
        # The mock is still on standby: it is what happens when both dry up.
        self.assertIsNotNone(service.mock)

    @override_settings(LUMA_API_KEY='live-key', **_MOCK_DISABLED)
    def test_provider_order_is_honoured(self):
        with override_settings(VIDEO_PROVIDER_ORDER='fal,luma'):
            # `fal` is not configured, so it is skipped rather than treated as
            # a failure — a partial config still works.
            self.assertEqual(_live_keys(get_luma_service()), ['luma'])


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

    @override_settings(**_NO_PROVIDERS)
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

    @override_settings(**_NO_PROVIDERS)
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

    @override_settings(**_NO_PROVIDERS)
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

    @override_settings(**_NO_PROVIDERS)
    def test_generate_returns_an_error_message_not_a_success_one(self):
        message, level = generate_story_video(self.contributor, self.story, 'a mask')

        self.assertEqual(level, 'error')
        self.assertIn('unavailable', message)
        self.assertNotIn('check back shortly', message)

    @override_settings(**_NO_PROVIDERS)
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


class MockFallbackTests(_ResetMemoisedService, TestCase):
    """The permissive default: answer the request, but never lie about it.

    `VIDEO_ALLOW_MOCK_FALLBACK` defaults to on, so a deployment whose providers
    have both gone quiet keeps serving rather than 502ing. The invariant that
    makes that survivable is attribution: the job must be stamped as the mock's
    work so nothing later credits a vendor that produced nothing.
    """

    def setUp(self):
        super().setUp()
        self.contributor = User.objects.create_user(
            'luma-fallback', email='luma-fallback@example.com',
            password='hunter2secure',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for video generation.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.client = APIClient()
        self.client.force_authenticate(self.contributor)

    @override_settings(LUMA_API_KEY='', FAL_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_a_server_with_no_provider_still_answers(self):
        service = get_luma_service()
        self.assertEqual(_live_keys(service), [])
        self.assertIsNotNone(service.mock)

    @override_settings(LUMA_API_KEY='', FAL_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_the_fallback_job_is_stamped_as_the_mocks_work(self):
        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': self.story.id,
            'prompt': 'a mask',
        }, format='json')

        self.assertEqual(resp.status_code, 201, resp.data)
        job = VideoGenerationJob.objects.get()
        self.assertEqual(job.provider, 'mock')
        self.assertEqual(job.engine, 'luma-mock')
        self.assertEqual(job.status, VideoGenerationJob.Status.PROCESSING)

    @override_settings(LUMA_API_KEY='', FAL_API_KEY='', LUMA_ALLOW_MOCK=False)
    def test_the_fallback_never_reaches_storage(self):
        """A placeholder URL must not be chased once per poll."""
        from media_app.services.video_storage import store_video_asset

        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='a mask',
            provider='mock',
            engine='luma-mock',
            status=VideoGenerationJob.Status.COMPLETED,
            video_url='https://storage.example.com/videos/x.mp4',
        )

        self.assertFalse(store_video_asset(job))
        self.assertFalse(job.video_file)
