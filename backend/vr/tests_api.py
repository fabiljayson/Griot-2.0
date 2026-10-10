"""HTTP tests for the VR launch and content endpoints."""

from unittest.mock import patch

from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from .factories import make_artifact, make_experience, make_story, make_user, place
from .models import VRSession

LAUNCH_URL = reverse('vr:launch')
EXCHANGE_URL = reverse('vr:launch-exchange')


class VRLaunchApiTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact, model_url='models/throne.glb')
        self.other_artifact = make_artifact('Lonely Stool')

    def launch(self, **body):
        return self.client.post(LAUNCH_URL, body, format='json')

    def test_anonymous_callers_cannot_mint_a_launch_token(self):
        response = self.launch(artifact=self.artifact.slug)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_launch_returns_a_single_use_token_and_a_deep_link(self):
        self.client.force_authenticate(self.user)

        response = self.launch(artifact=self.artifact.slug)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        body = response.json()
        self.assertTrue(body['token'])
        self.assertTrue(body['deep_link'].startswith('griotvr://launch?'))
        self.assertIn(f'artifact={self.artifact.pk}', body['deep_link'])
        self.assertIn(f'experience={self.experience.pk}', body['deep_link'])
        self.assertLessEqual(body['expires_in'], 120)
        self.assertEqual(body['experience']['scene_identifier'], 'bamoun_gallery')
        self.assertEqual(body['artifact']['slug'], self.artifact.slug)

    def test_launch_response_carries_no_credentials(self):
        self.client.force_authenticate(self.user)

        body = self.launch(artifact=self.artifact.slug).json()
        serialised = repr(body).lower()

        for forbidden in ('password', 'refresh', 'api_key', 'secret'):
            self.assertNotIn(forbidden, serialised)

    def test_launch_by_experience_id_and_slug(self):
        self.client.force_authenticate(self.user)

        by_id = self.launch(experience=self.experience.pk)
        by_slug = self.launch(experience=self.experience.slug)

        self.assertEqual(by_id.status_code, status.HTTP_201_CREATED)
        self.assertEqual(by_slug.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(by_slug.json()['artifact'])

    def test_launch_requires_an_experience_or_an_artifact(self):
        self.client.force_authenticate(self.user)

        response = self.client.post(LAUNCH_URL, {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_artifact_without_a_vr_experience_is_reported_distinctly(self):
        self.client.force_authenticate(self.user)

        response = self.launch(artifact=self.other_artifact.slug)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.json()['code'], 'no_vr_experience')

    def test_unpublished_artifacts_are_not_launchable(self):
        draft = make_artifact('Draft Piece', published=False)
        place(self.experience, draft, order=2)
        self.client.force_authenticate(self.user)

        response = self.launch(artifact=draft.slug)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.json()['code'], 'artifact_not_found')

    def test_inactive_experiences_are_not_launchable(self):
        closed = make_experience('Closed', active=False, scene_identifier='closed')
        piece = make_artifact('Closed Piece')
        place(closed, piece)
        self.client.force_authenticate(self.user)

        response = self.launch(experience=closed.slug)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_ambiguous_artifact_gets_a_conflict_rather_than_a_guess(self):
        second = make_experience('Second Gallery', scene_identifier='second_gallery')
        place(second, self.artifact, order=1)
        self.client.force_authenticate(self.user)

        response = self.launch(artifact=self.artifact.slug)

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(response.json()['code'], 'experience_ambiguous')

    def test_an_artifact_must_belong_to_the_named_experience(self):
        self.client.force_authenticate(self.user)

        response = self.launch(
            experience=self.experience.slug, artifact=self.other_artifact.slug,
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_launch_is_rate_limited(self):
        """Pins the throttle scope: an unlisted scope raises, it does not skip."""
        self.client.force_authenticate(self.user)

        with patch.dict(ScopedRateThrottle.THROTTLE_RATES, {'vr_launch': '2/min'}):
            first = self.launch(artifact=self.artifact.slug)
            second = self.launch(artifact=self.artifact.slug)
            third = self.launch(artifact=self.artifact.slug)

        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertEqual(third.status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class VRExchangeApiTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact, model_url='models/throne.glb')
        self.client.force_authenticate(self.user)

    def issue(self):
        return self.client.post(
            LAUNCH_URL, {'artifact': self.artifact.slug}, format='json',
        ).json()['token']

    def exchange(self, token, **extra):
        return self.client.post(
            EXCHANGE_URL, {'token': token, **extra}, format='json',
        )

    def test_exchange_opens_a_session_and_returns_a_vr_scoped_token(self):
        token = self.issue()
        self.client.force_authenticate(None)

        response = self.exchange(token, device_model='Quest 3')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()

        claims = AccessToken(body['access_token'])
        self.assertEqual(claims['scope'], 'vr')
        self.assertEqual(claims['experience'], self.experience.pk)

        session = VRSession.objects.get()
        self.assertEqual(claims['sid'], session.pk)
        self.assertEqual(session.device_model, 'Quest 3')
        self.assertEqual(session.user, self.user)
        self.assertEqual(session.completion_status, VRSession.Status.ACTIVE)

    def test_exchange_returns_the_full_experience_payload(self):
        token = self.issue()
        self.client.force_authenticate(None)

        body = self.exchange(token).json()

        experience = body['experience']
        self.assertEqual(experience['scene_identifier'], 'bamoun_gallery')
        self.assertEqual(experience['artifact_count'], 1)
        self.assertEqual(
            experience['artifacts'][0]['model_url'],
            'https://africanteller.org/media/models/throne.glb',
        )

    def test_exchange_never_returns_a_refresh_token(self):
        token = self.issue()
        self.client.force_authenticate(None)

        response = self.exchange(token)

        self.assertNotIn('refresh', response.json())
        self.assertNotIn('refresh', repr(response.json()).lower())

    def test_a_token_cannot_be_exchanged_twice(self):
        token = self.issue()
        self.client.force_authenticate(None)

        first = self.exchange(token)
        second = self.exchange(token)

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(second.json()['code'], 'token_used')
        self.assertEqual(VRSession.objects.count(), 1)

    def test_an_expired_token_reports_gone(self):
        from .models import VRLaunchToken

        token = self.issue()
        VRLaunchToken.objects.update(
            expires_at=VRLaunchToken.objects.get().created_at,
        )
        self.client.force_authenticate(None)

        response = self.exchange(token)

        self.assertEqual(response.status_code, status.HTTP_410_GONE)
        self.assertEqual(response.json()['code'], 'token_expired')
        self.assertFalse(VRSession.objects.exists())

    def test_a_garbage_token_is_rejected_without_leaking_why(self):
        self.client.force_authenticate(None)

        response = self.exchange('definitely-not-a-token')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.json()['code'], 'invalid_token')

    def test_a_deactivated_experience_is_refused_after_issue(self):
        token = self.issue()
        self.experience.is_active = False
        self.experience.save(update_fields=['is_active'])
        self.client.force_authenticate(None)

        response = self.exchange(token)

        self.assertEqual(response.status_code, status.HTTP_410_GONE)
        self.assertEqual(response.json()['code'], 'experience_unavailable')

    def test_exchange_does_not_require_a_reader_jwt(self):
        """The launch token is the credential; a header must not change whose
        session this is."""
        token = self.issue()
        self.client.force_authenticate(None)

        response = self.exchange(token)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(VRSession.objects.get().user, self.user)


class VRContentReadApiTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact, model_url='models/throne.glb')
        self.story = make_story('Procession')
        self.artifact.stories.add(self.story)

    def test_anonymous_callers_cannot_read_the_content_payloads(self):
        for url in (
            reverse('vr:experience-detail', args=[self.experience.slug]),
            reverse('vr:artifact-detail', args=[self.artifact.slug]),
        ):
            with self.subTest(url=url):
                self.assertEqual(
                    self.client.get(url).status_code,
                    status.HTTP_401_UNAUTHORIZED,
                )

    def test_experience_detail_is_readable_by_id_and_slug(self):
        self.client.force_authenticate(self.user)

        by_slug = self.client.get(
            reverse('vr:experience-detail', args=[self.experience.slug]),
        )
        by_id = self.client.get(
            reverse('vr:experience-detail', args=[self.experience.pk]),
        )

        self.assertEqual(by_slug.status_code, status.HTTP_200_OK)
        self.assertEqual(by_slug.json(), by_id.json())
        self.assertEqual(by_slug.json()['artifacts'][0]['slug'], self.artifact.slug)

    def test_unknown_experiences_return_404(self):
        self.client.force_authenticate(self.user)

        response = self.client.get(reverse('vr:experience-detail', args=['nope']))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_experience_detail_carries_the_learn_more_fields(self):
        """The serializer must ship what Unity's Learn More panel reads."""
        self.artifact.historical_significance = 'Used at royal enthronements.'
        self.artifact.source_url = 'https://example.org/throne'
        self.artifact.save(update_fields=['historical_significance', 'source_url'])
        self.client.force_authenticate(self.user)

        body = self.client.get(
            reverse('vr:experience-detail', args=[self.experience.slug]),
        ).json()

        artifact = body['artifacts'][0]
        self.assertEqual(artifact['historical_significance'], 'Used at royal enthronements.')
        self.assertEqual(artifact['source_url'], 'https://example.org/throne')

    def test_artifact_detail_lists_its_stories_and_experiences(self):
        self.client.force_authenticate(self.user)

        response = self.client.get(
            reverse('vr:artifact-detail', args=[self.artifact.slug]),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body['stories'][0]['id'], self.story.pk)
        self.assertEqual(body['experiences'][0]['id'], self.experience.pk)

    def test_artifact_list_filters_experiences_by_artifact(self):
        self.client.force_authenticate(self.user)
        make_experience('Other Gallery', scene_identifier='other_gallery')

        response = self.client.get(
            reverse('vr:experience-list'), {'artifact': self.artifact.slug},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.json()['results']
        self.assertEqual([item['id'] for item in results], [self.experience.pk])

    def test_an_unknown_artifact_filters_to_nothing(self):
        self.client.force_authenticate(self.user)

        response = self.client.get(
            reverse('vr:experience-list'), {'artifact': 'nope'},
        )

        self.assertEqual(response.json()['results'], [])

    def test_a_vr_scoped_token_reads_experiences(self):
        self.client.force_authenticate(self.user)
        token = self.client.post(
            LAUNCH_URL, {'artifact': self.artifact.slug}, format='json',
        ).json()['token']
        vr_token = self.client.post(
            EXCHANGE_URL, {'token': token}, format='json',
        ).json()['access_token']

        self.client.force_authenticate(None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {vr_token}')
        response = self.client.get(
            reverse('vr:experience-detail', args=[self.experience.slug]),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class VRReaderJwtOnVrOnlyEndpointsTests(APITestCase):
    """The `scope=vr` claim is checked, not merely set."""

    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.experience = make_experience()
        self.session = VRSession.objects.create(
            user=self.user, experience=self.experience,
        )

    def test_an_ordinary_jwt_cannot_start_or_complete_a_vr_session(self):
        self.client.force_authenticate(self.user)
        reader_token = str(RefreshToken.for_user(self.user).access_token)
        self.client.force_authenticate(None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {reader_token}')

        start = self.client.post(
            reverse('vr:session-start'), {'experience': self.experience.slug},
            format='json',
        )
        complete = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]), {}, format='json',
        )

        self.assertEqual(start.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(complete.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_vr_token_can_start_and_complete(self):
        from .services.session_tokens import mint_session_token

        encoded, _ = mint_session_token(user=self.user, session=self.session)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {encoded}')

        start = self.client.post(
            reverse('vr:session-start'), {'experience': self.experience.slug},
            format='json',
        )
        complete = self.client.post(
            reverse('vr:session-complete', args=[self.session.pk]),
            {'completion_status': 'completed', 'progress': 0.5},
            format='json',
        )

        self.assertEqual(start.status_code, status.HTTP_200_OK)
        self.assertEqual(complete.status_code, status.HTTP_200_OK)

    @override_settings(VR_SESSION_XP_COMPLETE=25)
    def test_an_expired_vr_token_is_refused(self):
        from datetime import timedelta

        from rest_framework_simplejwt.tokens import AccessToken

        token = AccessToken.for_user(self.user)
        token['scope'] = 'vr'
        token['sid'] = self.session.pk
        token.set_exp(lifetime=timedelta(seconds=-1))
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

        response = self.client.post(
            reverse('vr:session-start'), {'experience': self.experience.slug},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
