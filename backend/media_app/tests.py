from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

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
        self.client.force_authenticate(self.contributor)
    
    def test_create_audio_narration_job(self):
        url = reverse('media:audio-narration-list')
        resp = self.client.post(url, {
            'story_id': self.story.id,
            'language': 'en',
            'speed': 1.0,
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'processing')
    
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
        
        service = get_tts_service()
        
        # Submit job
        result = service.submit_narration(
            text='Hello, this is a test.',
            language='en',
        )
        self.assertIn('id', result)
        
        # List voices
        voices = service.list_voices('en')
        self.assertGreater(len(voices), 0)