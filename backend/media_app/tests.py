import tempfile
from io import StringIO
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import SimpleTestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from qr_codes.models import Artifact
from stories.models import Story

from .models import AudioNarrationJob, VideoGenerationJob

User = get_user_model()


class VideoGenerationTests(APITestCase):
    def setUp(self):
        self.contributor = User.objects.create_user(
            'contributor1',
            email='contrib1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for video generation.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.client.force_authenticate(self.contributor)
    
    def test_create_video_generation_job(self):
        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': self.story.id,
            'prompt': 'A beautiful African sunset over the savanna',
            'duration': 10,
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        # Submitted to Luma, so it is in flight rather than merely queued.
        self.assertEqual(resp.data['status'], 'processing')
        self.assertIn('luma_job_id', resp.data)
        self.assertNotEqual(resp.data['luma_job_id'], '')
        # The client reads these two keys to render the video.
        self.assertIn('story', resp.data)
        self.assertIn('video_url', resp.data)
    
    def test_list_video_jobs(self):
        # Create a job first
        VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='Test prompt',
            luma_job_id='test_123',
        )
        
        url = reverse('media:video-generation-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)
    
    def test_check_video_status(self):
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='Test prompt',
            luma_job_id='test_123',
            status=VideoGenerationJob.Status.PENDING,
        )
        
        url = reverse('media:video-generation-status', kwargs={'pk': job.id})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
    
    def test_cancel_video_job(self):
        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='Test prompt',
            luma_job_id='test_123',
            status=VideoGenerationJob.Status.PENDING,
        )
        
        url = reverse('media:video-generation-cancel', kwargs={'pk': job.id})
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        
        job.refresh_from_db()
        self.assertEqual(job.status, VideoGenerationJob.Status.FAILED)
    
    def test_any_user_can_generate_video_for_a_published_story(self):
        # Widened policy: a published story is open to any signed-in user,
        # mirroring the audio narration rule.
        other_user = User.objects.create_user(
            'other',
            email='other@example.com',
            password='hunter2secure',
        )
        other_story = Story.objects.create(
            title='Other Story',
            content='Another story.',
            author=other_user,
            status=Story.Status.PUBLISHED,
        )

        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': other_story.id,
            'prompt': 'Test prompt',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['story'], other_story.id)

    def test_cannot_generate_video_for_someone_elses_draft(self):
        other_user = User.objects.create_user(
            'other',
            email='other@example.com',
            password='hunter2secure',
        )
        draft = Story.objects.create(
            title='Private Draft',
            content='Not ready yet.',
            author=other_user,
            status=Story.Status.DRAFT,
        )

        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': draft.id,
            'prompt': 'Test prompt',
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_author_can_generate_video_for_their_own_draft(self):
        draft = Story.objects.create(
            title='My Draft',
            content='Mine.',
            author=self.contributor,
            status=Story.Status.DRAFT,
        )

        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': draft.id,
            'prompt': 'Test prompt',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_anonymous_user_cannot_start_a_generation(self):
        self.client.force_authenticate(None)
        url = reverse('media:video-generation-list')
        resp = self.client.post(url, {
            'story_id': self.story.id,
            'prompt': 'Test prompt',
        })
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    @override_settings(VIDEO_GENERATIONS_PER_USER_PER_DAY=2)
    def test_daily_cap_stops_unbounded_spend(self):
        url = reverse('media:video-generation-list')
        for _ in range(2):
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'prompt': 'Test prompt',
            })
            self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        resp = self.client.post(url, {
            'story_id': self.story.id,
            'prompt': 'One too many',
        })
        self.assertEqual(resp.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        self.assertIn('daily video generation', resp.data['detail'])
        self.assertEqual(
            VideoGenerationJob.objects.filter(user=self.contributor).count(), 2
        )

    @override_settings(VIDEO_GENERATIONS_PER_USER_PER_DAY=0)
    def test_daily_cap_can_be_disabled(self):
        url = reverse('media:video-generation-list')
        for _ in range(4):
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'prompt': 'Test prompt',
            })
            self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

    def test_luma_submission_failure_marks_the_job_failed(self):
        """A rejected submission must not leave a job pending forever."""
        from .services.luma_ai import LumaAIError

        failing = mock.Mock()
        failing.submit_video_generation.side_effect = LumaAIError(
            'Luma AI returned 402: payment required'
        )

        with mock.patch(
            'media_app.views.get_luma_service', return_value=failing
        ):
            url = reverse('media:video-generation-list')
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'prompt': 'Test prompt',
            })

        self.assertEqual(resp.status_code, status.HTTP_502_BAD_GATEWAY)

        job = VideoGenerationJob.objects.get(user=self.contributor)
        self.assertEqual(job.status, VideoGenerationJob.Status.FAILED)
        self.assertIn('payment required', job.error_message)

    def test_completed_job_exposes_the_keys_the_client_reads(self):
        """
        The Flutter client parses `story` and `video_url`. When these were
        named `story_id` / `url` on the client instead, every job parsed to
        storyId 0 with an empty url, so `isReady` was never true and a
        finished video could never play. Pin the wire contract.
        """
        from .services import luma_ai

        job = VideoGenerationJob.objects.create(
            user=self.contributor,
            story=self.story,
            prompt='Test prompt',
            luma_job_id='luma_abc123',
            status=VideoGenerationJob.Status.COMPLETED,
            video_url='https://cdn.example.com/clip.mp4',
            thumbnail_url='https://cdn.example.com/clip.jpg',
            duration=5,
        )

        completed = mock.Mock()
        completed.get_job_status.return_value = {
            'id': 'luma_abc123',
            'status': 'completed',
            'video_url': 'https://cdn.example.com/clip.mp4',
            'thumbnail_url': 'https://cdn.example.com/clip.jpg',
            'duration': 5,
        }

        with mock.patch(
            'media_app.views.get_luma_service', return_value=completed
        ):
            url = reverse('media:video-generation-status', kwargs={'pk': job.id})
            resp = self.client.get(url)

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'completed')
        self.assertEqual(resp.data['story'], self.story.id)
        self.assertEqual(
            resp.data['video_url'], 'https://cdn.example.com/clip.mp4'
        )
        self.assertEqual(resp.data['duration'], 5)
        self.assertNotIn('story_id', resp.data)
        self.assertNotIn('url', resp.data)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AudioNarrationTests(APITestCase):
    def setUp(self):
        self.contributor = User.objects.create_user(
            'contributor1',
            email='contrib1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='Test Story',
            content='A test story for audio narration.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.artifact = Artifact.objects.create(
            title='Royal Throne',
            description='A bronze throne from the Bamoun kingdom.',
            culture='Bamoun',
            region='West Region',
            is_published=True,
        )
        self.artifact.stories.add(self.story)
        self.client.force_authenticate(self.contributor)

    def _mock_tts_service(self):
        """Patch the TTS service so tests never hit the network."""
        service = mock.Mock()
        service.submit_narration.return_value = {
            'status': 'completed',
            'audio_bytes': b'ID3-fake-mp3-data',
            'filename': 'test-story-abc123.mp3',
            'duration': 12,
            'file_size': 19,
            'language': 'en',
            'voice_id': 'en',
        }
        return mock.patch('media_app.views.get_tts_service', return_value=service)

    def test_create_audio_narration_job(self):
        url = reverse('media:audio-narration-list')
        with self._mock_tts_service():
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'language': 'en',
                'speed': 1.0,
            })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'completed')
        self.assertTrue(resp.data['audio_url'].endswith('.mp3'))
        self.assertEqual(resp.data['duration'], 12)

        job = AudioNarrationJob.objects.get(id=resp.data['id'])
        self.assertTrue(job.audio_file)
        self.assertEqual(job.story, self.story)
        self.assertTrue(job.audio_file.name.startswith('audio/narrations/'))

    def test_create_audio_narration_for_artifact(self):
        """Audio guide: narration can be generated from an artifact."""
        url = reverse('media:audio-narration-list')
        with self._mock_tts_service():
            resp = self.client.post(url, {
                'artifact_id': self.artifact.id,
                'language': 'en',
            })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'completed')
        self.assertEqual(resp.data['artifact_id'], self.artifact.id)
        self.assertEqual(resp.data['story_title'], 'Test Story')

    def test_audio_requires_story_or_artifact(self):
        url = reverse('media:audio-narration-list')
        resp = self.client.post(url, {'language': 'en'})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_list_audio_jobs(self):
        AudioNarrationJob.objects.create(
            user=self.contributor,
            story=self.story,
            language='en',
        )
        
        url = reverse('media:audio-narration-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)


class ServiceTests(APITestCase):
    def test_luma_ai_service(self):
        from .services.luma_ai import get_luma_service
        
        service = get_luma_service()
        
        # Submit job
        result = service.submit_video_generation(
            prompt='Test prompt',
            duration=10,
        )
        self.assertIn('id', result)
        self.assertEqual(result['status'], 'pending')
        
        # Check status
        job_id = result['id']
        status_result = service.get_job_status(job_id)
        self.assertIn('status', status_result)
    
    def test_tts_service(self):
        from .services.tts import get_tts_service

        class FakeGTTS:
            def __init__(self, *args, **kwargs):
                pass

            def write_to_fp(self, fp):
                fp.write(b'ID3-fake-mp3-data')

        with mock.patch('media_app.services.tts.gTTS', FakeGTTS):
            service = get_tts_service()

            # Submit job
            result = service.submit_narration(
                text='Hello, this is a test.',
                language='en',
            )
            self.assertEqual(result['status'], 'completed')
            self.assertEqual(result['audio_bytes'], b'ID3-fake-mp3-data')
            self.assertGreater(result['file_size'], 0)
            self.assertGreater(result['duration'], 0)

        # List voices (no network needed)
        voices = service.list_voices('en')
        self.assertGreater(len(voices), 0)

    def test_tts_service_strips_markdown(self):
        from .services.tts import strip_markdown

        markdown = '# The Lion\n\nA **brave** tale of [the savanna](https://example.com).'
        plain = strip_markdown(markdown)
        self.assertNotIn('#', plain)
        self.assertNotIn('**', plain)
        self.assertIn('brave', plain)
        self.assertIn('the savanna', plain)

    def test_resolve_language_falls_back_to_english(self):
        from .services.tts import resolve_language

        self.assertEqual(resolve_language('en'), 'en')
        self.assertEqual(resolve_language('fr'), 'fr')
        self.assertEqual(resolve_language('ful'), 'en')  # unsupported -> en


class TTSSocketTimeoutTests(SimpleTestCase):
    """
    gTTS exposes no timeout argument, so the synthesis is wrapped in a
    process-wide default socket timeout. Without it a hung Google endpoint
    pins a worker forever; with it the call fails and the job is marked failed
    instead of hanging.
    """

    def test_timeout_is_applied_during_synthesis(self):
        import socket

        from .services.tts import _socket_timeout

        before = socket.getdefaulttimeout()
        with _socket_timeout(7.5):
            self.assertEqual(socket.getdefaulttimeout(), 7.5)
        self.assertEqual(socket.getdefaulttimeout(), before)

    def test_previous_timeout_is_restored_even_on_failure(self):
        import socket

        from .services.tts import _socket_timeout

        socket.setdefaulttimeout(3.0)
        try:
            with self.assertRaises(RuntimeError):
                with _socket_timeout(9.0):
                    raise RuntimeError('boom')
            self.assertEqual(socket.getdefaulttimeout(), 3.0)
        finally:
            socket.setdefaulttimeout(None)

    def test_missing_timeout_is_a_no_op(self):
        import socket

        from .services.tts import _socket_timeout

        before = socket.getdefaulttimeout()
        with _socket_timeout(None):
            self.assertEqual(socket.getdefaulttimeout(), before)

    @override_settings(TTS_SOCKET_TIMEOUT=5.0)
    def test_synthesis_runs_inside_the_timeout_guard(self):
        from .services import tts as tts_module

        seen = {}

        class ObservingGTTS:
            def __init__(self, *args, **kwargs):
                pass

            def write_to_fp(self, fp):
                import socket
                seen['timeout'] = socket.getdefaulttimeout()
                fp.write(b'fake-mp3')

        with mock.patch.object(tts_module, 'gTTS', ObservingGTTS):
            service = tts_module.GTTSNarrationService()
            result = service.submit_narration(text='Hello there.')

        self.assertEqual(result['status'], 'completed')
        self.assertEqual(seen['timeout'], 5.0)


class LumaServiceConfigurationTests(SimpleTestCase):
    """
    `get_luma_service()` reads `settings.LUMA_API_KEY`. The key was never
    declared in any settings module, so the attribute never existed and the
    live client could never be selected — every deployment silently ran the
    mock, whose 'completed' jobs point at an unplayable placeholder URL.
    """

    def setUp(self):
        import media_app.services.luma_ai as luma_module
        self.module = luma_module
        luma_module._service_instance = None
        self.addCleanup(setattr, luma_module, '_service_instance', None)

    @override_settings(LUMA_API_KEY='secret-live-key')
    def test_live_service_selected_when_key_is_configured(self):
        service = self.module.get_luma_service()
        self.assertIsInstance(service, self.module.LiveLumaAIService)
        self.assertEqual(service.api_key, 'secret-live-key')

    @override_settings(LUMA_API_KEY='')
    def test_mock_service_selected_without_a_key(self):
        self.assertIsInstance(
            self.module.get_luma_service(), self.module.MockLumaAIService
        )

    def test_settings_module_declares_the_key(self):
        from django.conf import settings as django_settings

        # Present but empty unless the environment supplies one.
        self.assertTrue(hasattr(django_settings, 'LUMA_API_KEY'))

    def test_settings_module_declares_tuning_knobs(self):
        from django.conf import settings as django_settings

        self.assertTrue(hasattr(django_settings, 'TTS_SOCKET_TIMEOUT'))
        self.assertTrue(hasattr(django_settings, 'TTS_MAX_CHARS'))
        self.assertTrue(
            hasattr(django_settings, 'VIDEO_GENERATIONS_PER_USER_PER_DAY')
        )


class FakeGTTS:
    """Drop-in gTTS replacement that writes fake MP3 bytes."""

    def __init__(self, *args, **kwargs):
        pass

    def write_to_fp(self, fp):
        fp.write(b'ID3-fake-mp3-data')


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class SeedNarrationsTests(APITestCase):
    def setUp(self):
        admin_user, _ = User.objects.get_or_create(
            username='admin',
            defaults={'role': 'admin', 'is_staff': True, 'is_superuser': True},
        )
        self.story = Story.objects.create(
            title='Seed Story',
            content='A **published** story for seeding.',
            author=admin_user,
            status=Story.Status.PUBLISHED,
        )
        self.artifact = Artifact.objects.create(
            title='Seed Mask',
            description='A ceremonial mask.',
            culture='Bamoun',
            is_published=True,
        )
        self.artifact.stories.add(self.story)

    def _run_command(self, **kwargs):
        with mock.patch('media_app.services.tts.gTTS', FakeGTTS):
            call_command(
                'seed_narrations',
                stdout=StringIO(),
                stderr=StringIO(),
                **kwargs,
            )

    def test_seed_narrations_generates_story_and_artifact_audio(self):
        self._run_command()

        jobs = AudioNarrationJob.objects.filter(
            status=AudioNarrationJob.Status.COMPLETED
        )
        self.assertEqual(jobs.count(), 2)
        for job in jobs:
            self.assertTrue(job.audio_file)
            self.assertGreater(job.file_size, 0)

        story_job = jobs.get(artifact=None)
        self.assertEqual(story_job.story, self.story)
        self.assertIn('published', story_job.narration_text)

        artifact_job = jobs.get(artifact=self.artifact)
        self.assertEqual(artifact_job.artifact, self.artifact)
        self.assertEqual(artifact_job.story, self.story)  # primary story linked

    def test_seed_narrations_is_idempotent_without_force(self):
        self._run_command()
        self._run_command()  # second run should skip everything

        self.assertEqual(
            AudioNarrationJob.objects.filter(
                status=AudioNarrationJob.Status.COMPLETED
            ).count(),
            2,
        )

    def test_seed_narrations_dry_run_creates_nothing(self):
        self._run_command(dry_run=True)
        self.assertEqual(AudioNarrationJob.objects.count(), 0)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class AudioNarrationCachingTests(APITestCase):
    def setUp(self):
        self.contributor = User.objects.create_user(
            'contributor1',
            email='contrib1@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='Cached Story',
            content='A story with pre-generated audio.',
            author=self.contributor,
            status=Story.Status.PUBLISHED,
        )
        self.artifact = Artifact.objects.create(
            title='Cached Mask',
            description='A cached artifact.',
            is_published=True,
        )
        self.client.force_authenticate(self.contributor)

    def _seed_job(self, *, story=None, artifact=None):
        with mock.patch('media_app.services.tts.gTTS', FakeGTTS):
            call_command(
                'seed_narrations',
                stdout=StringIO(),
                stderr=StringIO(),
            )
        return AudioNarrationJob.objects.get(
            story=story, artifact=artifact, language='en'
        )

    def test_create_reuses_pre_seeded_narration(self):
        seeded = self._seed_job(story=self.story, artifact=None)

        url = reverse('media:audio-narration-list')
        with mock.patch('media_app.views.get_tts_service') as tts_mock:
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'language': 'en',
            })

        # Cached job returned; no new synthesis happened.
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['id'], seeded.id)
        self.assertEqual(resp.data['status'], 'completed')
        tts_mock.return_value.submit_narration.assert_not_called()

    def test_create_reuses_artifact_audio_guide(self):
        seeded = self._seed_job(story=None, artifact=self.artifact)

        url = reverse('media:audio-narration-list')
        with mock.patch('media_app.views.get_tts_service') as tts_mock:
            resp = self.client.post(url, {
                'artifact_id': self.artifact.id,
            })

        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['id'], seeded.id)
        tts_mock.return_value.submit_narration.assert_not_called()

    def test_create_generates_when_no_cached_narration(self):
        # No seeding performed — a fresh POST must synthesize.
        url = reverse('media:audio-narration-list')
        service = mock.Mock()
        service.submit_narration.return_value = {
            'status': 'completed',
            'audio_bytes': b'ID3-fake-mp3-data',
            'filename': 'fresh-story-abc123.mp3',
            'duration': 9,
            'file_size': 19,
            'language': 'en',
            'voice_id': 'en',
        }
        with mock.patch('media_app.views.get_tts_service', return_value=service):
            resp = self.client.post(url, {
                'story_id': self.story.id,
                'language': 'en',
            })

        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'completed')
        service.submit_narration.assert_called_once()

class VideoProgressTests(APITestCase):
    """Render progress must actually reach the client.

    The status action originally copied status/video_url/thumbnail_url/duration
    but never progress, and no service reported it, so `progress_percent` was
    pinned at 0 for the entire render — including on a *completed* job. The
    story screen renders that number, so the user watched a dead meter.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            'progress_user',
            email='progress@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.story = Story.objects.create(
            title='Progress Story',
            content='A story used to check progress reporting.',
            author=self.user,
            status=Story.Status.PUBLISHED,
        )
        self.client.force_authenticate(self.user)

    def _job(self, **kwargs):
        defaults = {
            'user': self.user,
            'story': self.story,
            'luma_job_id': 'luma_progress_1',
            'status': VideoGenerationJob.Status.PROCESSING,
            'progress_percent': 0,
        }
        defaults.update(kwargs)
        return VideoGenerationJob.objects.create(**defaults)

    def _status_with(self, luma_status):
        job = self._job()
        service = mock.Mock()
        service.get_job_status.return_value = luma_status
        with mock.patch('media_app.views.get_luma_service', return_value=service):
            resp = self.client.get(
                reverse('media:video-generation-status', args=[job.id])
            )
        job.refresh_from_db()
        return resp, job

    def test_completion_forces_progress_to_100(self):
        resp, job = self._status_with({
            'status': 'completed',
            'video_url': 'https://example.com/v.mp4',
            'thumbnail_url': 'https://example.com/t.jpg',
            'duration': 7,
            'progress': 0,
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(job.progress_percent, 100)
        self.assertEqual(resp.data['progress_percent'], 100)
        self.assertIsNotNone(job.completed_at)

    def test_completion_ignores_a_stale_zero_progress(self):
        # The exact production symptom: completed while progress stayed 0.
        _, job = self._status_with({
            'status': 'completed',
            'video_url': 'https://example.com/v.mp4',
            'progress': 0,
        })
        self.assertEqual(job.progress_percent, 100)

    def test_in_progress_progress_is_persisted(self):
        _, job = self._status_with({
            'status': 'in_progress',
            'progress': 0.42,
            'video_url': '',
        })
        self.assertEqual(job.progress_percent, 42)
        self.assertIsNotNone(job.started_at)

    def test_progress_is_clamped_and_survives_garbage(self):
        _, job = self._status_with({'status': 'in_progress', 'progress': 9000})
        self.assertEqual(job.progress_percent, 100)

        _, job = self._status_with({'status': 'in_progress', 'progress': 'n/a'})
        self.assertEqual(job.progress_percent, 50)

        _, job = self._status_with({'status': 'in_progress', 'progress': None})
        self.assertEqual(job.progress_percent, 50)

    def test_fractional_and_percentage_forms_agree(self):
        from media_app.services.luma_ai import _normalise_progress

        self.assertEqual(_normalise_progress(0.42, 'in_progress'), 42)
        self.assertEqual(_normalise_progress(42, 'in_progress'), 42)
        self.assertEqual(_normalise_progress(1.0, 'in_progress'), 100)
        self.assertEqual(_normalise_progress(0, 'queued'), 0)
        self.assertEqual(_normalise_progress(None, 'completed'), 100)
        self.assertEqual(_normalise_progress(True, 'in_progress'), 50)
        self.assertEqual(_normalise_progress(-5, 'in_progress'), 0)

    def test_pending_promotes_to_processing_on_poll(self):
        job = self._job(status=VideoGenerationJob.Status.PENDING)
        service = mock.Mock()
        service.get_job_status.return_value = {
            'status': 'in_progress', 'progress': 10, 'video_url': '',
        }
        with mock.patch('media_app.views.get_luma_service', return_value=service):
            self.client.get(reverse('media:video-generation-status', args=[job.id]))
        job.refresh_from_db()
        self.assertEqual(job.status, VideoGenerationJob.Status.PROCESSING)
