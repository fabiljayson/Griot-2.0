"""Progress read/write and the locations discovery endpoint."""

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from .factories import make_artifact, make_experience, make_user, place
from .models import VRSession
from .services.progress import (
    SessionNotActive,
    progress_entries,
    record_progress,
)
from .services.session_tokens import mint_session_token
from .services.sessions import InvalidSessionArtifacts, start_session

PROGRESS_URL = reverse('vr:progress')
LOCATIONS_URL = reverse('vr:location-list')


def vr_token_for(user, session):
    encoded, _ = mint_session_token(user=user, session=session)
    return encoded


class ProgressServiceTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.other_user = make_user('visitor2')
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)

    def test_one_entry_per_experience_newest_first(self):
        second = make_experience('Second Gallery', scene_identifier='second_gallery')
        place(second, self.artifact)
        start_session(user=self.user, experience=self.experience)
        start_session(user=self.user, experience=second)

        entries = progress_entries(user=self.user)

        self.assertEqual(
            [entry['experience']['scene_identifier'] for entry in entries],
            ['second_gallery', 'bamoun_gallery'],
        )

    def test_a_completed_session_reads_as_one_hundred_percent(self):
        session = start_session(user=self.user, experience=self.experience)
        record_progress(session=session, progress=0.4)
        session.completion_status = VRSession.Status.COMPLETED
        session.save(update_fields=['completion_status'])

        entry = progress_entries(user=self.user)[0]

        self.assertTrue(entry['completed'])
        self.assertEqual(entry['completion_percentage'], 100)

    def test_visits_aggregate_count_percentage_and_last_seen(self):
        first = start_session(user=self.user, experience=self.experience)
        record_progress(session=first, progress=0.3)
        first.completion_status = VRSession.Status.ABANDONED
        first.save(update_fields=['completion_status'])
        second = start_session(user=self.user, experience=self.experience)
        record_progress(session=second, progress=0.65)

        entry = progress_entries(user=self.user)[0]

        self.assertEqual(entry['session_count'], 2)
        self.assertEqual(entry['completion_percentage'], 65)
        self.assertFalse(entry['completed'])
        self.assertEqual(entry['last_seen_at'], second.start_time)

    def test_only_the_callers_sessions_are_reported(self):
        start_session(user=self.other_user, experience=self.experience)

        self.assertEqual(progress_entries(user=self.user), [])

    def test_entries_can_be_filtered_by_experience_slug_or_id(self):
        other = make_experience('Other Gallery', scene_identifier='other_gallery')
        place(other, self.artifact)
        start_session(user=self.user, experience=self.experience)
        start_session(user=self.user, experience=other)

        by_slug = progress_entries(user=self.user, experience_key=self.experience.slug)
        by_id = progress_entries(user=self.user, experience_key=str(self.experience.pk))

        self.assertEqual(len(by_slug), 1)
        self.assertEqual(by_slug, by_id)

    def test_record_progress_writes_and_clamps(self):
        session = start_session(user=self.user, experience=self.experience)

        record_progress(session=session, progress=1.7)
        self.assertEqual(session.progress, 1.0)

        record_progress(session=session, progress=-0.2)
        self.assertEqual(session.progress, 0.0)

    def test_record_progress_replaces_the_viewed_list(self):
        session = start_session(user=self.user, experience=self.experience)
        record_progress(session=session, artifact_ids=[self.artifact.pk])

        record_progress(session=session, artifact_ids=[])

        self.assertEqual(list(session.artifacts_viewed.all()), [])

    def test_artifacts_outside_the_experience_are_refused(self):
        session = start_session(user=self.user, experience=self.experience)
        stranger = make_artifact('Not In This Gallery')

        with self.assertRaises(InvalidSessionArtifacts):
            record_progress(session=session, artifact_ids=[stranger.pk])

    def test_a_closed_session_cannot_be_progressed(self):
        session = start_session(user=self.user, experience=self.experience)
        session.completion_status = VRSession.Status.COMPLETED
        session.save(update_fields=['completion_status'])

        with self.assertRaises(SessionNotActive):
            record_progress(session=session, progress=0.5)

    def test_partial_progress_awards_no_xp(self):
        session = start_session(user=self.user, experience=self.experience)

        record_progress(session=session, progress=0.9)

        self.assertEqual(session.xp_awarded, 0)


class ProgressApiTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)
        self.session = start_session(user=self.user, experience=self.experience)
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {vr_token_for(self.user, self.session)}',
        )

    def test_reading_progress_anonymously_is_refused(self):
        self.client.credentials(HTTP_AUTHORIZATION='')

        response = self.client.get(PROGRESS_URL)

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_reading_progress_returns_the_rollup(self):
        response = self.client.get(PROGRESS_URL)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(len(body), 1)
        self.assertEqual(body[0]['experience']['id'], self.experience.pk)
        self.assertEqual(body[0]['completion_percentage'], 0)
        self.assertFalse(body[0]['completed'])
        self.assertEqual(body[0]['session_count'], 1)

    def test_reading_progress_works_with_a_reader_jwt_too(self):
        reader_token = str(AccessToken.for_user(self.user))
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {reader_token}')

        response = self.client.get(PROGRESS_URL)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_reading_progress_filters_by_experience(self):
        response = self.client.get(PROGRESS_URL, {'experience': 'nope'})

        self.assertEqual(response.json(), [])

    def test_patching_records_partial_progress(self):
        response = self.client.patch(
            PROGRESS_URL, {'progress': 0.65}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()['progress'], 0.65)
        self.session.refresh_from_db()
        self.assertEqual(self.session.progress, 0.65)

    def test_posting_progress_is_an_alias_of_patching(self):
        response = self.client.post(
            PROGRESS_URL, {'progress': 0.25}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()['progress'], 0.25)

    def test_progress_is_clamped_at_the_serializer_too(self):
        response = self.client.patch(
            PROGRESS_URL, {'progress': 5.0}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_empty_body_is_refused(self):
        response = self.client.patch(PROGRESS_URL, {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_ordinary_reader_jwt_cannot_drive_the_session(self):
        reader_token = str(AccessToken.for_user(self.user))
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {reader_token}')

        response = self.client.patch(PROGRESS_URL, {'progress': 0.5}, format='json')

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_progress_on_a_finished_session_is_a_conflict(self):
        self.session.completion_status = VRSession.Status.COMPLETED
        self.session.save(update_fields=['completion_status'])

        response = self.client.patch(PROGRESS_URL, {'progress': 0.5}, format='json')

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(response.json()['code'], 'session_not_active')

    def test_artifacts_outside_the_experience_are_a_400(self):
        stranger = make_artifact('Not In This Gallery')

        response = self.client.patch(
            PROGRESS_URL, {'artifacts_viewed': [stranger.pk]}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.json()['code'], 'invalid_artifacts')

    def test_recorded_artifacts_are_stored(self):
        response = self.client.patch(
            PROGRESS_URL, {'artifacts_viewed': [self.artifact.pk]}, format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.json()['artifacts_viewed'], [self.artifact.pk],
        )

    def test_partial_progress_pays_nothing(self):
        self.client.patch(PROGRESS_URL, {'progress': 0.9}, format='json')

        self.session.refresh_from_db()
        self.assertEqual(self.session.xp_awarded, 0)

    def test_a_vr_token_without_a_session_claim_is_refused(self):
        token = AccessToken.for_user(self.user)
        token['scope'] = 'vr'
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

        response = self.client.patch(PROGRESS_URL, {'progress': 0.5}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.json()['code'], 'missing_session')


class LocationApiTests(APITestCase):
    def setUp(self):
        cache.clear()

    def test_locations_are_public(self):
        response = self.client.get(LOCATIONS_URL)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json(), [])

    def test_locations_group_experiences_by_place(self):
        make_experience()
        make_experience(
            'Ndop Textile Room', scene_identifier='ndop_room',
            region='Northwest Region', culture='Bamileke',
        )

        response = self.client.get(LOCATIONS_URL)

        body = response.json()
        self.assertEqual(len(body), 2)
        entry = next(item for item in body if item['region'] == 'West Region')
        self.assertEqual(entry['museum_name'], 'Foumban Royal Museum')
        self.assertEqual(entry['culture'], 'Bamoun')
        self.assertEqual(entry['experience_count'], 1)
        self.assertEqual(entry['experiences'][0]['scene_identifier'], 'bamoun_gallery')

    def test_inactive_experiences_are_not_destinations(self):
        make_experience('Closed Gallery', active=False, scene_identifier='closed')

        self.assertEqual(self.client.get(LOCATIONS_URL).json(), [])
