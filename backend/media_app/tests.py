import tempfile
from io import StringIO
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import override_settings
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
        self.assertEqual(resp.data['status'], 'pending')
        self.assertIn('luma_job_id', resp.data)
    
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
    
    def test_cannot_generate_video_for_others_story(self):
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
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)


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