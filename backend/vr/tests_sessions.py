"""Session lifecycle: progress recording, XP awards, and their idempotency."""

from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from gamification.models import UserProfile

from .factories import make_artifact, make_experience, make_user, place
from .models import VRSession
from .services.session_tokens import mint_session_token
from .services.sessions import (
    InvalidCompletionStatus,
    InvalidSessionArtifacts,
    complete_session,
    find_active_session,
    start_session,
    validate_artifact_ids,
)


class SessionServiceTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)

    def test_completing_awards_xp_to_the_existing_profile(self):
        session = start_session(user=self.user, experience=self.experience)

        session, xp_awarded = complete_session(
            session=session,
            completion_status=VRSession.Status.COMPLETED,
            progress=0.9,
            duration_seconds=420,
        )

        self.assertEqual(xp_awarded, 25)
        self.assertEqual(session.xp_awarded, 25)
        self.assertEqual(session.completion_status, VRSession.Status.COMPLETED)
        self.assertEqual(session.progress, 0.9)
        self.assertEqual(session.duration_seconds, 420)
        self.assertIsNotNone(session.end_time)
        self.assertEqual(UserProfile.objects.get(user=self.user).total_xp, 25)

    def test_completing_twice_does_not_pay_twice(self):
        """Unity retrying over a flaky link is the normal case, not the error case."""
        session = start_session(user=self.user, experience=self.experience)
        complete_session(session=session, completion_status=VRSession.Status.COMPLETED)

        session, xp_awarded = complete_session(
            session=session, completion_status=VRSession.Status.COMPLETED,
        )

        self.assertEqual(xp_awarded, 0)
        self.assertEqual(session.xp_awarded, 25)
        self.assertEqual(UserProfile.objects.get(user=self.user).total_xp, 25)

    def test_an_abandoned_session_pays_nothing(self):
        session = start_session(user=self.user, experience=self.experience)

        session, xp_awarded = complete_session(
            session=session, completion_status=VRSession.Status.ABANDONED,
        )

        self.assertEqual(xp_awarded, 0)
        self.assertEqual(session.xp_awarded, 0)
        self.assertFalse(UserProfile.objects.filter(user=self.user).exists())

    @override_settings(VR_SESSION_XP_COMPLETE=0)
    def test_the_reward_can_be_disabled(self):
        session = start_session(user=self.user, experience=self.experience)

        _, xp_awarded = complete_session(
            session=session, completion_status=VRSession.Status.COMPLETED,
        )

        self.assertEqual(xp_awarded, 0)

    def test_an_unknown_status_is_refused(self):
        session = start_session(user=self.user, experience=self.experience)

        with self.assertRaises(InvalidCompletionStatus):
            complete_session(session=session, completion_status='teleported')

    def test_progress_is_clamped_to_zero_and_one(self):
        session = start_session(user=self.user, experience=self.experience)

        session, _ = complete_session(
            session=session, completion_status=VRSession.Status.COMPLETED, progress=4.2,
        )
        self.assertEqual(session.progress, 1.0)

        session, _ = complete_session(
            session=session, completion_status=VRSession.Status.COMPLETED, progress=-3.0,
        )
        self.assertEqual(session.progress, 0.0)

    def test_duration_falls_back_to_wall_clock_when_the_client_sends_none(self):
        session = start_session(user=self.user, experience=self.experience)

        session, _ = complete_session(
            session=session, completion_status=VRSession.Status.COMPLETED,
        )

        self.assertGreaterEqual(
            session.duration_seconds,
            int((timezone.now() - session.start_time).total_seconds()) - 1,
        )

    def test_artifacts_outside_the_experience_are_refused(self):
        stranger = make_artifact('Not In This Gallery')

        with self.assertRaises(InvalidSessionArtifacts):
            validate_artifact_ids(self.experience, [stranger.pk])

    def test_artifacts_must_be_whole_numbers(self):
        with self.assertRaises(InvalidSessionArtifacts):
            validate_artifact_ids(self.experience, ['one'])

    def test_recorded_artifacts_are_stored(self):
        session = start_session(user=self.user, experience=self.experience)

        session, _ = complete_session(
            session=session,
            completion_status=VRSession.Status.COMPLETED,
            artifact_ids=[self.artifact.pk],
        )

        self.assertEqual(
            list(session.artifacts_viewed.values_list('pk', flat=True)),
            [self.artifact.pk],
        )

    def test_an_active_session_is_resumable(self):
        first = start_session(user=self.user, experience=self.experience)

        self.assertEqual(
            find_active_session(user=self.user, experience=self.experience), first,
        )

        complete_session(session=first, completion_status=VRSession.Status.COMPLETED)

        self.assertIsNone(
            find_active_session(user=self.user, experience=self.experience),
        )


class SessionApiTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.other_user = make_user('visitor2')
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)
        self.session = start_session(user=self.user, experience=self.experience)
        encoded, _ = mint_session_token(user=self.user, session=self.session)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {encoded}')

    def test_starting_a_session_returns_the_existing_one(self):
        response = self.client.post(
            reverse('vr:session-start'),
            {'experience': self.experience.slug},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()['id'], self.session.pk)
        self.assertEqual(VRSession.objects.count(), 1)

    def test_starting_a_session_for_a_new_experience_creates_one(self):
        second = make_experience('Second Gallery', scene_identifier='second_gallery')
        place(second, self.artifact)

        response = self.client.post(
            reverse('vr:session-start'), {'experience': second.slug}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.json()['experience'], second.pk)

    def test_starting_an_unknown_experience_is_404(self):
        response = self.client.post(
            reverse('vr:session-start'), {'experience': 'nope'}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.json()['code'], 'experience_not_found')

    def test_completing_reports_the_xp_and_the_profile(self):
        response = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]),
            {'completion_status': 'completed', 'progress': 0.75, 'duration_seconds': 300},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body['xp_awarded'], 25)
        self.assertEqual(body['profile']['total_xp'], 25)
        self.assertEqual(body['session']['progress'], 0.75)
        self.assertEqual(body['session']['completion_status'], 'completed')

    def test_a_retried_completion_reports_zero_xp(self):
        payload = {'completion_status': 'completed'}

        first = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]), payload, format='json',
        )
        second = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]), payload, format='json',
        )

        self.assertEqual(first.json()['xp_awarded'], 25)
        self.assertEqual(second.json()['xp_awarded'], 0)
        self.assertEqual(UserProfile.objects.get(user=self.user).total_xp, 25)

    def test_an_artifact_from_another_experience_is_a_400(self):
        stranger = make_artifact('Not In This Gallery')

        response = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]),
            {'completion_status': 'completed', 'artifacts_viewed': [stranger.pk]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.json()['code'], 'invalid_artifacts')

    def test_another_readers_session_is_not_reachable(self):
        foreign = start_session(user=self.other_user, experience=self.experience)

        response = self.client.post(
            reverse('vr:session-complete', args=[foreign.pk]),
            {'completion_status': 'completed'},
            format='json',
        )

        # 404 rather than 403: a 403 would confirm the row exists.
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
