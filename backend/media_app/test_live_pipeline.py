"""End-to-end proof of the media pipeline against real external services.

Every other test in this suite stubs gTTS and Luma out, which is correct for CI
but means a green suite says nothing about whether the real integration works.
This module exercises the full path — real routing, real auth, real permission
checks, real gTTS synthesis, real file storage — and asserts the exact response
keys the Flutter client parses.

It talks to Google, so it is opt-in and skipped by default::

    RUN_LIVE_TTS_TESTS=1 python manage.py test media_app.test_live_pipeline

The narration assertions are deliberately strict. The original defect was that
a failed synthesis returned HTTP 201 with ``status='failed'`` and the client
treated the response as success, so "the request returned 201" is not evidence
of anything. These tests require real MPEG audio bytes.
"""

import os
import unittest

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.storage import default_storage
from django.test import override_settings
from django.urls import reverse
from rest_framework import status as http_status
from rest_framework.test import APITestCase

from stories.models import Story

from .models import AudioNarrationJob, VideoGenerationJob

User = get_user_model()

LIVE = os.environ.get('RUN_LIVE_TTS_TESTS') == '1'

requires_live_tts = unittest.skipUnless(
    LIVE,
    'Set RUN_LIVE_TTS_TESTS=1 to run live gTTS integration tests.',
)


@requires_live_tts
class LiveNarrationPipelineTests(APITestCase):
    """Real gTTS synthesis through the real narration endpoint."""

    def setUp(self):
        self.author = User.objects.create_user(
            'live_author',
            email='live_author@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.listener = User.objects.create_user(
            'live_listener',
            email='live_listener@example.com',
            password='hunter2secure',
            role='visitor',
        )
        self.story = Story.objects.create(
            title='The Talking Pot',
            content=(
                'In the village of Bafut there lived a pot that spoke. '
                'Every morning it warned the children not to walk too far.'
            ),
            author=self.author,
            status=Story.Status.PUBLISHED,
        )

    def test_visitor_gets_real_playable_audio_for_a_published_story(self):
        self.client.force_authenticate(self.listener)
        response = self.client.post(
            reverse('media:audio-narration-list'),
            {'story_id': self.story.id, 'language': 'en'},
            format='json',
        )

        self.assertEqual(
            response.status_code,
            http_status.HTTP_201_CREATED,
            msg=f'narration failed: {response.data}',
        )
        data = response.data

        # The whole point of the fix: a 201 is only a success if it carries
        # real audio. This is the assertion the old bug would have failed.
        self.assertEqual(
            data['status'],
            AudioNarrationJob.Status.COMPLETED,
            msg=f'gTTS did not complete: {data.get("error_message")}',
        )
        self.assertTrue(data['audio_url'], msg='completed job exposed no audio_url')

        job = AudioNarrationJob.objects.get(id=data['id'])
        self.assertTrue(job.audio_file, msg='completed job stored no file')
        self.assertGreater(job.file_size, 1024, msg='audio file is implausibly small')

        audio_bytes = job.audio_file.read()
        # ID3 tag, or an MPEG frame sync: 0xFF then a byte with its top three
        # bits set. Rules out HTML error pages and empty bodies, which is what
        # a silent gTTS failure actually returns.
        has_id3 = audio_bytes[:3] == b'ID3'
        has_frame_sync = len(audio_bytes) > 1 and audio_bytes[0] == 0xFF and (
            audio_bytes[1] & 0xE0
        ) == 0xE0
        self.assertTrue(
            has_id3 or has_frame_sync,
            msg=f'not MPEG audio: {audio_bytes[:16]!r}',
        )
        self.assertGreaterEqual(job.duration, 1)

    def test_unpublished_story_stays_private_to_its_author(self):
        draft = Story.objects.create(
            title='Draft Notes',
            content='This draft must not be narrated by strangers.',
            author=self.author,
            status=Story.Status.DRAFT,
        )
        self.client.force_authenticate(self.listener)
        response = self.client.post(
            reverse('media:audio-narration-list'),
            {'story_id': draft.id, 'language': 'en'},
            format='json',
        )
        self.assertEqual(response.status_code, http_status.HTTP_403_FORBIDDEN)


@requires_live_tts
class LiveRegistrationIdempotencyTests(APITestCase):
    """Cold starts make clients re-POST signup; the replay must be a 200."""

    def test_exact_replay_returns_200_not_a_false_duplicate_error(self):
        payload = {
            'username': 'live_replay_user',
            'email': 'live_replay_user@example.com',
            'password': 'hunter2secure',
            'first_name': 'Live',
            'last_name': 'Replay',
        }
        first = self.client.post(
            reverse('users:register'), payload, format='json'
        )
        self.assertEqual(first.status_code, http_status.HTTP_201_CREATED)

        replay = self.client.post(reverse('users:register'), payload, format='json')
        self.assertEqual(
            replay.status_code,
            http_status.HTTP_200_OK,
            msg=f'signup replay regressed to a duplicate error: {replay.data}',
        )
        self.assertEqual(replay.data['user']['id'], first.data['user']['id'])

    def test_replay_with_a_different_password_is_a_real_conflict(self):
        User.objects.create_user(
            'live_taken',
            email='live_taken@example.com',
            password='hunter2secure',
        )
        response = self.client.post(
            reverse('users:register'),
            {
                'username': 'live_taken',
                'email': 'live_taken@example.com',
                'password': 'a-completely-different-password',
            },
            format='json',
        )
        self.assertEqual(response.status_code, http_status.HTTP_400_BAD_REQUEST)


class VideoContractTests(APITestCase):
    """The video job JSON contract, asserted without touching the network.

    The Flutter client reads ``story`` and ``video_url``. The backend used to
    emit ``story_id`` and ``url``, so every job parsed to storyId 0 with an
    empty url and no finished video could ever become playable. These tests
    pin the keys the client depends on.
    """

    def setUp(self):
        self.author = User.objects.create_user(
            'contract_author',
            email='contract_author@example.com',
            password='hunter2secure',
            role='contributor',
        )
        self.visitor = User.objects.create_user(
            'contract_visitor',
            email='contract_visitor@example.com',
            password='hunter2secure',
            role='visitor',
        )
        self.published = Story.objects.create(
            title='Published Story',
            content='Anyone signed in may render this one.',
            author=self.author,
            status=Story.Status.PUBLISHED,
        )
        self.draft = Story.objects.create(
            title='Private Draft',
            content='Only the author may render this one.',
            author=self.author,
            status=Story.Status.DRAFT,
        )

    def test_completed_job_serializes_the_keys_the_client_parses(self):
        from django.utils import timezone

        job = VideoGenerationJob.objects.create(
            user=self.visitor,
            story=self.published,
            luma_job_id='luma-live-1',
            status=VideoGenerationJob.Status.COMPLETED,
            progress_percent=100,
            video_url='https://storage.example.com/video.mp4',
            thumbnail_url='https://storage.example.com/thumb.jpg',
            duration=8,
            completed_at=timezone.now(),
        )
        self.client.force_authenticate(self.visitor)
        response = self.client.get(
            reverse('media:video-generation-detail', args=[job.id])
        )
        self.assertEqual(response.status_code, http_status.HTTP_200_OK)

        data = response.data
        # Keys the Flutter VideoModel.fromJson requires.
        self.assertEqual(data['story'], self.published.id)
        self.assertEqual(
            data['video_url'], 'https://storage.example.com/video.mp4'
        )
        self.assertEqual(data['progress_percent'], 100)
        self.assertEqual(data['status'], VideoGenerationJob.Status.COMPLETED)

        # The old, wrong keys must not linger and shadow the correct ones.
        self.assertNotIn('story_id', data)
        self.assertNotIn('url', data)

    def test_visitor_may_start_a_video_for_a_published_story(self):
        self.client.force_authenticate(self.visitor)
        response = self.client.post(
            reverse('media:video-generation-list'),
            {
                'story_id': self.published.id,
                'prompt': 'A warm cinematic shot of the talking pot.',
            },
            format='json',
        )
        self.assertIn(
            response.status_code,
            (http_status.HTTP_200_OK, http_status.HTTP_201_CREATED),
            msg=f'published story rejected a signed-in user: {response.data}',
        )

    def test_visitor_is_refused_on_another_authors_draft(self):
        self.client.force_authenticate(self.visitor)
        response = self.client.post(
            reverse('media:video-generation-list'),
            {
                'story_id': self.draft.id,
                'prompt': 'A warm cinematic shot of the talking pot.',
            },
            format='json',
        )
        self.assertEqual(response.status_code, http_status.HTTP_403_FORBIDDEN)

    def test_daily_cap_stops_runaway_spend(self):
        cap = settings.VIDEO_GENERATIONS_PER_USER_PER_DAY
        VideoGenerationJob.objects.bulk_create(
            [
                VideoGenerationJob(
                    user=self.visitor,
                    story=self.published,
                    status=VideoGenerationJob.Status.COMPLETED,
                )
                for _ in range(cap)
            ]
        )
        self.client.force_authenticate(self.visitor)
        response = self.client.post(
            reverse('media:video-generation-list'),
            {
                'story_id': self.published.id,
                'prompt': 'A warm cinematic shot of the talking pot.',
            },
            format='json',
        )
        self.assertEqual(
            response.status_code,
            http_status.HTTP_429_TOO_MANY_REQUESTS,
            msg=f'daily cap did not engage: {response.data}',
        )


class LiveLumaServiceTests(APITestCase):
    """Confirms which Luma implementation the deployment would actually use."""

    def test_live_client_is_used_only_when_a_key_is_configured(self):
        from .services.luma_ai import get_luma_service

        has_key = bool(
            os.environ.get('LUMA_API_KEY')
            or getattr(settings, 'LUMA_API_KEY', '')
        )
        service = get_luma_service()
        self.assertEqual(
            type(service).__name__,
            'LiveLumaAIService' if has_key else 'MockLumaAIService',
            msg='Luma key present but the mock backend is active; video jobs '
            'will report completed with an unplayable placeholder URL.',
        )
