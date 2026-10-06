"""Unit tests for the VR domain: models, launch tokens, payload building."""

from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase, override_settings
from django.utils import timezone

from .factories import (
    make_artifact,
    make_experience,
    make_narration,
    make_story,
    make_user,
    place,
)
from .models import VRExperience, VRLaunchToken
from .services.experience_payload import (
    absolute_media_url,
    artifact_payload,
    experience_payload,
    narration_payload,
)
from .services.experiences import (
    AmbiguousVRExperience,
    NoVRExperience,
    active_experiences_for_artifact,
    find_experience_by_key,
    resolve_launch_experience,
)
from .services.launch_tokens import (
    ExpiredLaunchToken,
    InvalidLaunchToken,
    UsedLaunchToken,
    build_deep_link,
    consume_launch_token,
    hash_token,
    issue_launch_token,
)


class VRExperienceModelTests(TestCase):
    def test_slug_is_generated_from_the_title(self):
        experience = make_experience(title='Bamoun Heritage Gallery')
        self.assertEqual(experience.slug, 'bamoun-heritage-gallery')

    def test_experiences_default_to_inactive(self):
        """A scene that is not in a shipped build must not be launchable."""
        experience = VRExperience.objects.create(
            title='Unreleased', scene_identifier='unreleased_scene'
        )
        self.assertFalse(experience.is_active)


class AbsoluteMediaUrlTests(TestCase):
    @override_settings(SITE_URL='https://africanteller.org', MEDIA_URL='/media/')
    def test_each_reference_shape_resolves(self):
        self.assertEqual(
            absolute_media_url('https://cdn.example.org/a.mp3'),
            'https://cdn.example.org/a.mp3',
        )
        self.assertEqual(
            absolute_media_url('/media/audio/a.mp3'),
            'https://africanteller.org/media/audio/a.mp3',
        )
        self.assertEqual(
            absolute_media_url('audio/a.mp3'),
            'https://africanteller.org/media/audio/a.mp3',
        )

    def test_blank_inputs_are_none(self):
        self.assertIsNone(absolute_media_url(''))
        self.assertIsNone(absolute_media_url(None))


class NarrationPayloadTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.artifact = make_artifact()

    def test_only_completed_narrations_are_published(self):
        job = make_narration(
            self.user,
            artifact=self.artifact,
            status='pending',
        )
        self.assertIsNone(narration_payload(job))

    def test_completed_narration_carries_attribution(self):
        job = make_narration(self.user, artifact=self.artifact)
        payload = narration_payload(job)

        self.assertEqual(payload['audio_url'], 'https://cdn.example.org/audio/narration.mp3')
        self.assertEqual(payload['duration'], 84)
        # The headset has no page to check: it must be able to say the voice is
        # synthetic rather than let a listener assume a community recording.
        self.assertIn('is_synthetic', payload)
        self.assertIn('attribution', payload)

    def test_a_narration_with_no_playable_audio_is_dropped(self):
        job = make_narration(self.user, artifact=self.artifact, audio_url='')
        self.assertIsNone(narration_payload(job))


class ExperiencePayloadTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.artifact = make_artifact()
        self.experience = make_experience()
        place(self.experience, self.artifact, model_url='models/mask.glb')

    def test_payload_lists_placed_artifacts_with_their_assets(self):
        payload = experience_payload(self.experience)

        self.assertEqual(payload['scene_identifier'], 'bamoun_gallery')
        self.assertEqual(payload['artifact_count'], 1)
        self.assertEqual(payload['artifacts'][0]['slug'], self.artifact.slug)
        self.assertEqual(
            payload['artifacts'][0]['model_url'],
            'https://africanteller.org/media/models/mask.glb',
        )

    def test_unpublished_artifacts_are_excluded(self):
        draft = make_artifact('Draft Mask', published=False)
        place(self.experience, draft, order=1)

        payload = experience_payload(self.experience)

        self.assertEqual(payload['artifact_count'], 1)
        self.assertEqual(
            [item['id'] for item in payload['artifacts']],
            [self.artifact.pk],
        )

    def test_only_published_stories_are_referenced(self):
        published = make_story('Procession', status='published')
        draft = make_story('Unfinished', status='draft')
        self.artifact.stories.set([published, draft])

        payload = artifact_payload(self.artifact)

        self.assertEqual([story['id'] for story in payload['stories']], [published.pk])

    def test_payload_carries_no_credentials(self):
        """The headset is the least auditable client; nothing secret goes there."""
        payload = experience_payload(self.experience)
        serialised = repr(payload).lower()

        for forbidden in ('password', 'secret', 'api_key', 'token', 'refresh'):
            self.assertNotIn(forbidden, serialised)


class LaunchTokenServiceTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)

    def test_token_is_stored_only_as_a_hash(self):
        issued = issue_launch_token(
            user=self.user, experience=self.experience, artifact=self.artifact,
        )

        row = VRLaunchToken.objects.get()
        self.assertNotEqual(row.token_hash, issued.token)
        self.assertEqual(row.token_hash, hash_token(issued.token))
        # A database dump must not yield a working credential.
        self.assertNotIn(issued.token, str(row.__dict__))

    def test_consume_returns_the_bound_context(self):
        issued = issue_launch_token(
            user=self.user, experience=self.experience, artifact=self.artifact,
        )

        row = consume_launch_token(token=issued.token)

        self.assertEqual(row.user, self.user)
        self.assertEqual(row.experience, self.experience)
        self.assertEqual(row.artifact, self.artifact)
        self.assertIsNotNone(row.used_at)

    def test_a_token_is_single_use(self):
        issued = issue_launch_token(user=self.user, experience=self.experience)

        consume_launch_token(token=issued.token)

        with self.assertRaises(UsedLaunchToken):
            consume_launch_token(token=issued.token)

    def test_an_expired_token_is_refused(self):
        issued = issue_launch_token(user=self.user, experience=self.experience)
        VRLaunchToken.objects.update(expires_at=timezone.now() - timedelta(seconds=1))

        with self.assertRaises(ExpiredLaunchToken):
            consume_launch_token(token=issued.token)

    def test_unknown_and_malformed_tokens_are_refused(self):
        issue_launch_token(user=self.user, experience=self.experience)

        for candidate in ('', 'not-a-real-token', 'x' * 500, None):
            with self.subTest(candidate=candidate):
                with self.assertRaises(InvalidLaunchToken):
                    consume_launch_token(token=candidate)

    def test_the_token_ttl_is_short(self):
        issued = issue_launch_token(user=self.user, experience=self.experience)
        self.assertLessEqual(issued.ttl_seconds, 120)
        self.assertGreater(issued.ttl_seconds, 0)

    @override_settings(VR_LAUNCH_TOKEN_TTL_SECONDS=5)
    def test_the_ttl_is_configurable(self):
        issued = issue_launch_token(user=self.user, experience=self.experience)

        self.assertEqual(issued.ttl_seconds, 5)
        self.assertLessEqual(issued.expires_in, 5)

    def test_ttl_can_be_overridden_per_call(self):
        issued = issue_launch_token(
            user=self.user, experience=self.experience, ttl_seconds=30,
        )
        self.assertEqual(issued.ttl_seconds, 30)

    @override_settings(VR_DEEP_LINK_SCHEME='griotvr', VR_DEEP_LINK_HOST='launch')
    def test_deep_link_carries_only_the_token_and_ids(self):
        issued = issue_launch_token(
            user=self.user, experience=self.experience, artifact=self.artifact,
        )

        link = build_deep_link(
            token=issued.token, experience=self.experience, artifact=self.artifact,
        )

        self.assertTrue(link.startswith('griotvr://launch?'))
        self.assertIn('experience=%d' % self.experience.pk, link)
        self.assertIn('artifact=%d' % self.artifact.pk, link)
        self.assertIn(issued.token, link)
        # No credentials, no user identifier, no refresh token.
        for forbidden in ('password', 'refresh', 'api_key', 'user='):
            self.assertNotIn(forbidden, link)

    def test_deep_link_omits_the_artifact_when_there_is_none(self):
        issued = issue_launch_token(user=self.user, experience=self.experience)

        link = build_deep_link(token=issued.token, experience=self.experience)

        self.assertNotIn('artifact=', link)


class LaunchExperienceResolutionTests(TestCase):
    def setUp(self):
        self.experience = make_experience()
        self.artifact = make_artifact()
        place(self.experience, self.artifact)

    def test_an_artifact_resolves_to_its_only_experience(self):
        self.assertEqual(
            resolve_launch_experience(artifact=self.artifact),
            self.experience,
        )

    def test_an_artifact_in_no_experience_is_refused(self):
        lonely = make_artifact('Lonely Stool')

        with self.assertRaises(NoVRExperience):
            resolve_launch_experience(artifact=lonely)

    def test_an_inactive_experience_is_refused(self):
        make_experience('Closed Gallery', active=False, scene_identifier='closed')

        # The artifact only exists in the active experience, so the answer is
        # still NoVRExperience rather than a launch into the closed one.
        experimental = make_artifact('Experimental Piece')
        closed = VRExperience.objects.get(scene_identifier='closed')
        place(closed, experimental)

        with self.assertRaises(NoVRExperience):
            resolve_launch_experience(artifact=experimental)

    def test_an_ambiguous_artifact_asks_the_caller_to_choose(self):
        second = make_experience('Second Gallery', scene_identifier='second_gallery')
        place(second, self.artifact, order=1)

        with self.assertRaises(AmbiguousVRExperience):
            resolve_launch_experience(artifact=self.artifact)

    def test_an_explicit_experience_wins(self):
        second = make_experience('Second Gallery', scene_identifier='second_gallery')
        place(second, self.artifact, order=1)

        self.assertEqual(
            resolve_launch_experience(
                experience_key=str(second.pk), artifact=self.artifact,
            ),
            second,
        )

    def test_an_artifact_outside_the_named_experience_is_refused(self):
        other = make_artifact('Another Piece')

        with self.assertRaises(NoVRExperience):
            resolve_launch_experience(
                experience_key=str(self.experience.pk), artifact=other,
            )

    def test_experiences_resolve_by_id_and_by_slug(self):
        self.assertEqual(
            find_experience_by_key(str(self.experience.pk)), self.experience,
        )
        self.assertEqual(
            find_experience_by_key(self.experience.slug), self.experience,
        )
        self.assertIsNone(find_experience_by_key('nope'))

    def test_artifact_experience_lookup_ignores_inactive_experiences(self):
        second = make_experience(
            'Closed', active=False, scene_identifier='closed_gallery',
        )
        place(second, self.artifact, order=1)

        self.assertEqual(
            list(active_experiences_for_artifact(self.artifact)),
            [self.experience],
        )


class SessionXpSettingTests(TestCase):
    @override_settings(VR_SESSION_XP_COMPLETE=7)
    def test_reward_is_configurable(self):
        from .services.sessions import session_xp_reward

        self.assertEqual(session_xp_reward(), 7)

    def test_reward_can_be_disabled(self):
        from .services.sessions import session_xp_reward

        with override_settings(VR_SESSION_XP_COMPLETE=0):
            self.assertEqual(session_xp_reward(), 0)


class SessionTokenTests(TestCase):
    def setUp(self):
        self.user = make_user()
        self.experience = make_experience()

    def test_minted_token_is_vr_scoped_and_session_bound(self):
        from rest_framework_simplejwt.tokens import AccessToken

        from .services.session_tokens import mint_session_token
        from .services.sessions import start_session

        session = start_session(user=self.user, experience=self.experience)
        encoded, lifetime = mint_session_token(user=self.user, session=session)

        token = AccessToken(encoded)
        self.assertEqual(token['scope'], 'vr')
        self.assertEqual(token['sid'], session.pk)
        self.assertEqual(token['experience'], self.experience.pk)
        self.assertLessEqual(lifetime, 45 * 60)

    def test_no_refresh_token_is_issued(self):
        from .services.session_tokens import mint_session_token
        from .services.sessions import start_session

        session = start_session(user=self.user, experience=self.experience)
        encoded, _ = mint_session_token(user=self.user, session=session)

        # A refresh token would let the headset extend its own access; the
        # bounded lifetime is the point of the whole flow.
        self.assertNotIn('refresh', encoded.lower())


class LaunchTokenHashingTests(TestCase):
    def test_hashing_is_deterministic_and_not_the_identity(self):
        token = 'abc123'
        self.assertEqual(hash_token(token), hash_token(token))
        self.assertNotEqual(hash_token(token), token)
        self.assertEqual(len(hash_token(token)), 64)

    def test_token_bytes_are_url_safe(self):
        with patch('vr.services.launch_tokens.secrets.token_urlsafe') as mocked:
            mocked.return_value = 'stub-token'
            user = make_user()
            experience = make_experience()
            issued = issue_launch_token(user=user, experience=experience)

        mocked.assert_called_once_with(32)
        self.assertEqual(issued.token, 'stub-token')
