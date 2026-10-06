"""The fallback chain: what happens when one vendor can no longer answer.

The migration's motivating failure was a single-provider outage — Luma's
retired endpoint returned 403 for every key, so every video request 502'd until
somebody noticed. The chain is the fix, and these tests pin the decisions that
make it useful rather than merely present:

* order is honoured, and an unconfigured provider is *absent*, not a failure;
* "I am out of credits" advances; "this prompt is refused" stops;
* the mock may stand in when every live provider is gone, but only when the
  setting allows it, and never without saying whose work it is;
* polls route by ``provider`` because a job id is only meaningful to the vendor
  that issued it.

The fal.ai client is covered here too — it is the provider the chain reaches
for first in practice, and its queue contract has two traps (``COMPLETED`` also
means failed; the model id is baked into every URL).
"""

from unittest import mock

from django.test import SimpleTestCase, override_settings

from media_app.services.video_providers import (
    ProviderRejected,
    ProviderUnavailable,
    VideoProviderChain,
    build_video_service,
    reset_video_service,
)
from media_app.services.video_providers.base import result_field
from media_app.services.video_providers.fal import (
    DEFAULT_FAL_MODEL,
    QUEUE_BASE,
    FalProvider,
    _pack_job_id,
    _unpack_job_id,
)
from media_app.services.video_providers.mock import MockVideoProvider


class _Response:
    def __init__(self, status_code=200, payload=None, text=''):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self):
        return self._payload


class _FakeProvider:
    """A provider whose failure mode is a script, so a test can read as prose."""

    def __init__(self, key, engine, outcome):
        self.key = key
        self.engine = engine
        self.live = True
        self.configured = True
        self._outcome = outcome
        self.submitted = []

    def submit_video_generation(self, prompt, **kwargs):
        if isinstance(self._outcome, Exception):
            raise self._outcome
        self.submitted.append(prompt)
        if self._outcome is None:
            return {
                'id': f'{self.key}_1', 'status': 'pending', 'engine': self.engine,
            }
        return dict(self._outcome)

    def get_job_status(self, job_id):
        return {'id': job_id, 'status': 'in_progress'}

    def cancel_job(self, job_id):
        return {'id': job_id, 'status': 'cancelled'}


def _ok(provider_key, engine):
    return {'id': f'{provider_key}_1', 'status': 'pending', 'engine': engine}


class ChainFallbackTests(SimpleTestCase):
    def test_the_first_provider_that_answers_serves(self):
        first = _FakeProvider('luma', 'luma-ray-3.2', _ok('luma', 'luma-ray-3.2'))
        second = _FakeProvider('fal', 'fal-std', _ok('fal', 'fal-std'))
        chain = VideoProviderChain([first, second])

        result = chain.submit_video_generation(prompt='a mask')

        self.assertEqual(result['id'], 'luma_1')
        self.assertEqual(second.submitted, [])

    def test_out_of_credits_falls_through_to_the_next_provider(self):
        first = _FakeProvider(
            'luma', 'luma-ray-3.2',
            ProviderUnavailable('Luma AI unavailable (402): Not enough credits'),
        )
        second = _FakeProvider('fal', 'fal-std', _ok('fal', 'fal-std'))
        chain = VideoProviderChain([first, second])

        result = chain.submit_video_generation(prompt='a mask')

        self.assertEqual(result['id'], 'fal_1')
        self.assertEqual(result['provider'], 'fal')
        self.assertEqual(second.submitted, ['a mask'])

    def test_a_rejection_stops_instead_of_replaying_the_refusal_elsewhere(self):
        first = _FakeProvider(
            'luma', 'luma-ray-3.2',
            ProviderRejected('Luma AI rejected the request (422): moderated'),
        )
        second = _FakeProvider('fal', 'fal-std', _ok('fal', 'fal-std'))
        chain = VideoProviderChain([first, second])

        with self.assertRaises(ProviderRejected):
            chain.submit_video_generation(prompt='a moderated prompt')

        self.assertEqual(second.submitted, [])

    def test_an_unconfigured_provider_is_skipped_not_counted_as_a_failure(self):
        # `VideoProviderChain.__init__` filters on `.configured`.
        absent = _FakeProvider('fal', 'fal-std', _ok('fal', 'fal-std'))
        absent.configured = False
        second = _FakeProvider('mock-ish', 'x', _ok('x', 'x'))
        chain = VideoProviderChain([absent, second])

        self.assertEqual(chain.submit_video_generation(prompt='a')['id'], 'x_1')

    def test_every_provider_out_falls_back_to_the_mock(self):
        first = _FakeProvider(
            'luma', 'luma-ray-3.2', ProviderUnavailable('402')
        )
        second = _FakeProvider('fal', 'fal-std', ProviderUnavailable('401'))
        chain = VideoProviderChain([first, second], mock=MockVideoProvider())

        result = chain.submit_video_generation(prompt='a mask')

        self.assertEqual(result['provider'], 'mock')
        self.assertEqual(result['engine'], 'luma-mock')

    def test_every_provider_out_raises_when_the_mock_is_disallowed(self):
        chain = VideoProviderChain(
            [_FakeProvider('luma', 'e', ProviderUnavailable('402'))],
            mock=None,
        )

        with self.assertRaises(ProviderUnavailable) as ctx:
            chain.submit_video_generation(prompt='a mask')

        # The reason must name the provider, or the operator has nothing to go on.
        self.assertIn('luma: 402', str(ctx.exception))

    def test_a_chain_with_nothing_at_all_raises(self):
        with self.assertRaises(ProviderUnavailable) as ctx:
            VideoProviderChain([]).submit_video_generation(prompt='a mask')
        self.assertIn('no live provider configured', str(ctx.exception))

    def test_the_mock_is_only_reached_after_every_live_provider_tried(self):
        first = _FakeProvider('luma', 'e', ProviderUnavailable('402'))
        second = _FakeProvider('fal', 'e', _ok('fal', 'fal-std'))
        chain = VideoProviderChain([first, second], mock=MockVideoProvider())

        chain.submit_video_generation(prompt='a mask')

        self.assertEqual(first.submitted, [])
        self.assertEqual(second.submitted, ['a mask'])

    def test_an_empty_chain_is_not_configured(self):
        self.assertFalse(VideoProviderChain([]).configured)
        self.assertTrue(
            VideoProviderChain([], mock=MockVideoProvider()).configured
        )

    def test_engine_reports_the_first_live_provider_or_the_mocks(self):
        self.assertEqual(
            VideoProviderChain(
                [_FakeProvider('luma', 'luma-ray-3.2', None)]
            ).engine,
            'luma-ray-3.2',
        )
        self.assertEqual(
            VideoProviderChain([], mock=MockVideoProvider()).engine,
            'luma-mock',
        )
        self.assertEqual(VideoProviderChain([]).engine, '')


class ChainRoutingTests(SimpleTestCase):
    """Polls and cancels go to the vendor that issued the job id."""

    def setUp(self):
        self.luma = _FakeProvider('luma', 'luma-ray-3.2', None)
        self.luma.get_job_status = mock.Mock(
            return_value={'status': 'in_progress', 'from': 'luma'}
        )
        self.fal = _FakeProvider('fal', 'fal-std', None)
        self.fal.get_job_status = mock.Mock(
            return_value={'status': 'in_progress', 'from': 'fal'}
        )
        self.chain = VideoProviderChain(
            [self.luma, self.fal], mock=MockVideoProvider()
        )

    def test_a_job_is_polled_against_the_provider_that_created_it(self):
        self.assertEqual(
            self.chain.get_job_status('model|req', provider='fal')['from'],
            'fal',
        )
        self.luma.get_job_status.assert_not_called()

    def test_an_empty_provider_falls_back_to_the_primary(self):
        # Rows written before the `provider` column existed.
        self.chain.get_job_status('gen_1', provider='')
        self.luma.get_job_status.assert_called_once_with('gen_1')

    def test_an_unknown_provider_is_not_guessed_at(self):
        # Polling a different vendor with someone else's job id is worse than
        # saying the provider is gone.
        result = self.chain.get_job_status('gen_1', provider='veo')

        self.assertEqual(result['status'], 'unknown')
        self.luma.get_job_status.assert_not_called()
        self.fal.get_job_status.assert_not_called()

    def test_a_mock_job_is_polled_against_the_mock(self):
        # The mock's real implementation reads the job row from the database;
        # this test only cares that routing reached it.
        with mock.patch.object(
            MockVideoProvider,
            'get_job_status',
            return_value={'status': 'in_progress', 'from': 'mock'},
        ) as poll:
            result = self.chain.get_job_status('luma_abc', provider='mock')

        poll.assert_called_once_with('luma_abc')
        self.assertEqual(result['from'], 'mock')
        self.luma.get_job_status.assert_not_called()

    def test_cancelling_an_unknown_provider_still_succeeds_locally(self):
        # The user's intent is honoured even with nothing to cancel.
        result = self.chain.cancel_job('gen_1', provider='veo')
        self.assertEqual(result['status'], 'cancelled')


class FalProviderTests(SimpleTestCase):
    def setUp(self):
        self.service = FalProvider(api_key='test-key')

    def test_auth_is_key_not_bearer(self):
        """fal rejects `Bearer`; a copy-pasted Luma header fails silently."""
        self.assertEqual(
            self.service._session.headers['Authorization'], 'Key test-key'
        )

    def test_submit_posts_to_the_model_specific_queue_url(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(200, {'request_id': 'abc-123'}),
        ) as post:
            result = self.service.submit_video_generation(
                prompt='a mask', duration=10
            )

        self.assertEqual(post.call_args.args[0], f'{QUEUE_BASE}/{DEFAULT_FAL_MODEL}')
        payload = post.call_args.kwargs['json']
        self.assertEqual(payload['prompt'], 'a mask')
        self.assertEqual(payload['duration'], 10)
        # The model id travels inside the id so a poll survives a config change.
        self.assertEqual(result['id'], f'{DEFAULT_FAL_MODEL}|abc-123')
        self.assertEqual(result['provider'], 'fal')
        self.assertEqual(result['status'], 'pending')

    def test_duration_is_snapped_to_what_the_model_accepts(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(200, {'request_id': 'r'}),
        ) as post:
            self.service.submit_video_generation(prompt='x', duration=12)
            self.service.submit_video_generation(prompt='x', duration=5)

        self.assertEqual(post.call_args_list[0].kwargs['json']['duration'], 10)
        self.assertEqual(post.call_args_list[1].kwargs['json']['duration'], 5)

    def test_an_out_of_credits_submit_advances_the_chain(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(
                402, {'detail': 'Insufficient queue credits'}
            ),
        ):
            with self.assertRaises(ProviderUnavailable) as ctx:
                self.service.submit_video_generation(prompt='a mask')

        self.assertIn('402', str(ctx.exception))

    def test_a_moderated_prompt_stops_the_chain(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(422, {'detail': 'Prompt was rejected'}),
        ):
            with self.assertRaises(ProviderRejected):
                self.service.submit_video_generation(prompt='a mask')

    # --- job id packing --------------------------------------------------

    def test_the_job_id_round_trips_model_and_request(self):
        packed = _pack_job_id(DEFAULT_FAL_MODEL, 'req-1')
        self.assertEqual(_unpack_job_id(packed), (DEFAULT_FAL_MODEL, 'req-1'))

    def test_an_id_without_a_model_falls_back_to_the_configured_one(self):
        """Ids written before the separator existed must still resolve."""
        model, request_id = _unpack_job_id('legacy-request')
        self.assertEqual(model, DEFAULT_FAL_MODEL)
        self.assertEqual(request_id, 'legacy-request')

    def test_polling_survives_a_model_change_mid_flight(self):
        job_id = _pack_job_id(DEFAULT_FAL_MODEL, 'req-1')
        with override_settings(
            FAL_VIDEO_MODEL='fal-ai/some-other-model'
        ):
            self.assertEqual(_unpack_job_id(job_id)[0], DEFAULT_FAL_MODEL)

    # --- status ----------------------------------------------------------

    def test_status_polls_the_url_the_job_id_embeds(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(200, {'status': 'IN_PROGRESS'}),
        ) as get:
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(
            get.call_args.args[0], f'{QUEUE_BASE}/m/requests/req-1/status'
        )
        self.assertEqual(result['status'], 'in_progress')
        self.assertEqual(result['progress'], 50)

    def test_a_queued_request_reads_as_pending(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(200, {'status': 'IN_QUEUE', 'queue_position': 3}),
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'pending')
        self.assertEqual(result['progress'], 0)

    def test_a_failed_request_still_reports_completed(self):
        """The trap: fal uses COMPLETED for both outcomes."""
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(
                200,
                {
                    'status': 'COMPLETED',
                    'error': 'Model crashed',
                    'error_type': 'RuntimeError',
                },
            ),
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['error'], 'Model crashed (RuntimeError)')
        self.assertEqual(result['video_url'], '')

    def test_a_completed_request_fetches_the_result_payload(self):
        with mock.patch.object(
            self.service._session,
            'get',
            side_effect=[
                _Response(200, {'status': 'COMPLETED'}),
                _Response(200, {'video': {'url': 'https://v/x.mp4', 'duration': 5}}),
            ],
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['video_url'], 'https://v/x.mp4')
        self.assertEqual(result['duration'], 5)
        self.assertEqual(result['progress'], 100)

    def test_the_videos_array_schema_is_also_recognised(self):
        with mock.patch.object(
            self.service._session,
            'get',
            side_effect=[
                _Response(200, {'status': 'COMPLETED'}),
                _Response(200, {'videos': [{'url': 'https://v/y.mp4'}]}),
            ],
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['video_url'], 'https://v/y.mp4')

    def test_completed_without_a_url_is_a_failure_not_an_empty_success(self):
        with mock.patch.object(
            self.service._session,
            'get',
            side_effect=[
                _Response(200, {'status': 'COMPLETED'}),
                _Response(200, {}),
            ],
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'failed')
        self.assertIn('no video URL', result['error'])

    def test_a_transport_error_while_fetching_the_result_keeps_waiting(self):
        """The render finished and was paid for; losing the fetch must not fail it."""
        import requests as http_requests

        with mock.patch.object(
            self.service._session,
            'get',
            side_effect=[
                _Response(200, {'status': 'COMPLETED'}),
                http_requests.ConnectionError('reset'),
            ],
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'in_progress')

    def test_status_transport_error_degrades_to_in_progress(self):
        import requests as http_requests

        with mock.patch.object(
            self.service._session, 'get', side_effect=http_requests.Timeout('slow')
        ):
            result = self.service.get_job_status('m|req-1')

        self.assertEqual(result['status'], 'in_progress')
        self.assertIn('error', result)

    def test_cancel_posts_to_the_cancel_url(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(200, {}),
        ) as post:
            result = self.service.cancel_job('m|req-1')

        self.assertEqual(
            post.call_args.args[0], f'{QUEUE_BASE}/m/requests/req-1/cancel'
        )
        self.assertEqual(result['status'], 'cancelled')

    def test_cancel_never_raises(self):
        import requests as http_requests

        with mock.patch.object(
            self.service._session, 'post', side_effect=http_requests.Timeout('slow')
        ):
            result = self.service.cancel_job('m|req-1')

        self.assertIn('error', result)


class VideoServiceFactoryTests(SimpleTestCase):
    """What the factory hands the app, given a set of keys."""

    def setUp(self):
        reset_video_service()
        self.addCleanup(reset_video_service)

    @override_settings(
        LUMA_API_KEY='luma-key', FAL_API_KEY='fal-key',
        LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=True,
    )
    def test_both_keys_build_both_providers_in_order(self):
        chain = build_video_service()
        self.assertEqual([p.key for p in chain.providers], ['luma', 'fal'])
        self.assertIsNotNone(chain.mock)

    @override_settings(
        LUMA_API_KEY='luma-key', FAL_API_KEY='',
        LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=True,
    )
    def test_only_the_configured_provider_is_present(self):
        chain = build_video_service()
        self.assertEqual([p.key for p in chain.providers], ['luma'])

    @override_settings(
        LUMA_API_KEY='', FAL_API_KEY='',
        LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=False,
    )
    def test_nothing_configured_raises_with_the_variable_to_set(self):
        with self.assertRaises(ProviderUnavailable) as ctx:
            build_video_service()

        self.assertIn('LUMA_API_KEY', str(ctx.exception))
        self.assertIn('FAL_API_KEY', str(ctx.exception))

    @override_settings(
        LUMA_API_KEY='', FAL_API_KEY='',
        LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=True,
    )
    def test_the_mock_fallback_answers_when_nothing_is_configured(self):
        chain = build_video_service()
        self.assertEqual(chain.providers, [])
        self.assertIsNotNone(chain.mock)

    @override_settings(
        LUMA_API_KEY='', FAL_API_KEY='',
        LUMA_ALLOW_MOCK=True, VIDEO_ALLOW_MOCK_FALLBACK=False,
    )
    def test_the_legacy_mock_opt_in_still_works(self):
        chain = build_video_service()
        self.assertIsNotNone(chain.mock)

    @override_settings(
        LUMA_API_KEY='', FAL_API_KEY='',
        LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=False,
    )
    def test_a_failed_lookup_is_not_memoised(self):
        with self.assertRaises(ProviderUnavailable):
            build_video_service()

        with override_settings(
            LUMA_API_KEY='late-key', FAL_API_KEY='', LUMA_ALLOW_MOCK=False,
        ):
            self.assertEqual(
                [p.key for p in build_video_service().providers], ['luma']
            )

    @override_settings(
        VIDEO_PROVIDER_ORDER='fal,luma', LUMA_API_KEY='', FAL_API_KEY='f',
        LUMA_ALLOW_MOCK=False,
    )
    def test_provider_order_follows_the_setting(self):
        chain = build_video_service()
        self.assertEqual([p.key for p in chain.providers], ['fal'])

    @override_settings(
        VIDEO_PROVIDER_ORDER='not-a-provider', LUMA_API_KEY='',
        FAL_API_KEY='', LUMA_ALLOW_MOCK=False, VIDEO_ALLOW_MOCK_FALLBACK=True,
    )
    def test_an_unknown_provider_name_is_ignored(self):
        chain = build_video_service()
        self.assertEqual(chain.providers, [])
        # It is skipped, not fatal: the chain still builds what it can.
        self.assertIsNotNone(chain.mock)


class ResultFieldTests(SimpleTestCase):
    """Why `result_field` exists rather than a bare `result.get(...)`."""

    def test_a_real_string_is_read(self):
        self.assertEqual(result_field({'engine': 'luma-ray'}, 'engine'), 'luma-ray')

    def test_a_missing_key_falls_back_to_the_default(self):
        self.assertEqual(result_field({}, 'engine', 'unknown'), 'unknown')

    def test_a_mock_returning_a_mock_does_not_reach_a_charfield(self):
        import unittest.mock as stdlib_mock

        self.assertEqual(
            result_field(stdlib_mock.Mock(), 'engine', 'unknown'), 'unknown'
        )

    def test_a_non_string_is_rejected(self):
        # A test double often returns Mock(), int, or None for any key.
        for value in (42, None, ['luma']):
            with self.subTest(value=value):
                self.assertEqual(
                    result_field({'engine': value}, 'engine', 'unknown'),
                    'unknown',
                )
