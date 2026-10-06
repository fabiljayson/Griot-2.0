"""The video client must not turn an upstream network fault into a 500.

Two distinct failure modes were unguarded in the original Luma client:

* `submit_video_generation` only raised `LumaAIError` for an HTTP error status.
  A connect timeout, DNS failure or connection reset raised
  `requests.RequestException`, which the view does not catch — so a stalled
  network produced a 500 instead of the 502 the view already returns for other
  upstream failures, and the `VideoGenerationJob` row was left permanently
  PENDING with no recorded reason.
* `get_job_status` had no guard at all. It is called on every poll of
  `/api/videos/{id}/status/`; a transport error there broke the client's poll
  loop and discarded the progress already recorded, even though the render was
  still running on the vendor's side.

The polling path is the important one: it must degrade to "still in progress",
never to an error.

The second half of this module pins the Luma Agents API contract itself, which
is what changed during the migration off the retired Dream Machine endpoint.
Those are the details a well-tested client silently got wrong: the payload
shape, the fixed duration enum, and which HTTP statuses mean "fall through to
the next provider" versus "this input is bad everywhere".
"""

from unittest import mock

import requests
from django.test import SimpleTestCase

from media_app.services.luma_ai import (
    LUMA_API_BASE,
    LiveLumaAIService,
    LumaAIError,
    _normalise_progress,
)
from media_app.services.video_providers.base import (
    ProviderRejected,
    ProviderUnavailable,
)
from media_app.services.video_providers.luma import (
    DEFAULT_LUMA_MODEL,
    LUMA_AGENTS_API_BASE,
    luma_duration,
)

TIMEOUT = requests.exceptions.ConnectTimeout('connection timed out')


class _Response:
    def __init__(self, status_code=200, payload=None, text=''):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


class LiveLumaTimeoutTests(SimpleTestCase):
    def setUp(self):
        self.service = LiveLumaAIService(api_key='test-key')

    # --- submit ---------------------------------------------------------

    def test_submit_translates_a_timeout_into_luma_ai_error(self):
        with mock.patch.object(
            self.service._session, 'post', side_effect=TIMEOUT
        ):
            with self.assertRaises(LumaAIError) as ctx:
                self.service.submit_video_generation(prompt='a story')

        # The view catches LumaAIError, records the failure on the job, and
        # answers 502. The exception must be the one the view knows about.
        self.assertIn('Could not reach Luma AI', str(ctx.exception))

    def test_submit_preserves_the_original_exception_as_the_cause(self):
        with mock.patch.object(
            self.service._session, 'post', side_effect=TIMEOUT
        ):
            with self.assertRaises(LumaAIError) as ctx:
                self.service.submit_video_generation(prompt='a story')

        self.assertIsInstance(ctx.exception.__cause__, requests.RequestException)

    def test_submit_still_raises_luma_ai_error_on_http_error(self):
        with mock.patch.object(
            self.service._session, 'post', return_value=_Response(500, text='boom')
        ):
            with self.assertRaises(LumaAIError) as ctx:
                self.service.submit_video_generation(prompt='a story')

        self.assertIn('500', str(ctx.exception))

    # --- poll -----------------------------------------------------------

    def test_status_degrades_to_in_progress_on_timeout(self):
        with mock.patch.object(
            self.service._session, 'get', side_effect=TIMEOUT
        ):
            result = self.service.get_job_status('luma_abc')

        # The view branches on `status`: anything other than completed/failed
        # persists progress and leaves the job running. A transport error must
        # land there so the poll loop survives.
        self.assertEqual(result['status'], 'in_progress')
        self.assertIn('error', result)

    def test_status_does_not_report_completed_on_a_transport_error(self):
        """The dangerous case: a failed poll must never look like a result."""
        with mock.patch.object(
            self.service._session, 'get', side_effect=TIMEOUT
        ):
            result = self.service.get_job_status('luma_abc')

        self.assertNotEqual(result.get('status'), 'completed')
        self.assertEqual(result.get('video_url', ''), '')

    def test_status_preserves_the_404_path(self):
        with mock.patch.object(
            self.service._session, 'get', return_value=_Response(404)
        ):
            result = self.service.get_job_status('luma_abc')

        self.assertEqual(result['status'], 'unknown')

    def test_status_preserves_the_http_error_path(self):
        with mock.patch.object(
            self.service._session, 'get', return_value=_Response(503)
        ):
            result = self.service.get_job_status('luma_abc')

        self.assertEqual(result['status'], 'unknown')
        self.assertIn('503', result['error'])

    def test_status_happy_path_still_works(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(
                200,
                {'state': 'completed', 'assets': {'video': 'https://v/x.mp4'}},
            ),
        ):
            result = self.service.get_job_status('luma_abc')

        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['video_url'], 'https://v/x.mp4')
        self.assertEqual(result['progress'], 100)

    # --- cancel ---------------------------------------------------------

    def test_cancel_makes_no_http_request_at_all(self):
        """The Agents API has no DELETE route (it answers 405).

        Calling it anyway would log a scary error on every user-initiated
        cancel. The operation degrades to "cancelled locally", which is what
        the view reports to the user regardless of what the vendor would say.
        """
        with mock.patch.object(self.service._session, 'delete') as delete:
            result = self.service.cancel_job('luma_abc')

        delete.assert_not_called()
        self.assertEqual(result['status'], 'cancelled')

    def test_cancel_never_raises_for_an_unsupported_operation(self):
        # `VideoProvider.cancel_job` is documented as best-effort; the chain
        # and the view both call it without a guard.
        with mock.patch.object(
            self.service._session, 'delete', side_effect=TIMEOUT
        ):
            result = self.service.cancel_job('luma_abc')

        self.assertEqual(result['status'], 'cancelled')
        self.assertIn('provider has no cancel API', result['message'])

    # --- transport configuration ---------------------------------------

    def test_session_has_an_explicit_timeout(self):
        """Without this, a stalled socket pins a worker indefinitely."""
        self.assertIsNotNone(self.service._session.timeout)
        connect, read = self.service._session.timeout
        self.assertGreater(connect, 0)
        self.assertGreater(read, 0)

    def test_the_live_base_is_the_agents_host_over_https(self):
        self.assertTrue(LUMA_AGENTS_API_BASE.startswith('https://'))
        self.assertIn('agents.lumalabs.ai', LUMA_AGENTS_API_BASE)
        # The retired host must never creep back in as the one we call.
        self.assertNotEqual(LUMA_AGENTS_API_BASE, LUMA_API_BASE)


class LumaAgentsApiContractTests(SimpleTestCase):
    """Everything about the new API that a well-tested client can still get wrong."""

    def setUp(self):
        self.service = LiveLumaAIService(api_key='test-key')

    # --- request payload ------------------------------------------------

    def test_submit_posts_the_agents_payload_shape(self):
        with mock.patch.object(
            self.service._session, 'post', return_value=_Response(201, {'id': 'gen_1'})
        ) as post:
            self.service.submit_video_generation(prompt='a mask', duration=5)

        url = post.call_args.args[0]
        self.assertEqual(url, f'{LUMA_AGENTS_API_BASE}/generations')
        payload = post.call_args.kwargs['json']
        self.assertEqual(payload['model'], DEFAULT_LUMA_MODEL)
        self.assertEqual(payload['type'], 'video')
        self.assertEqual(payload['prompt'], 'a mask')
        self.assertEqual(payload['aspect_ratio'], '16:9')
        self.assertEqual(payload['video']['duration'], '5s')
        self.assertEqual(payload['video']['resolution'], '720p')

    def test_duration_is_snapped_to_a_value_the_api_accepts(self):
        # Ray 3.2 takes "5s" or "10s" only; anything else is a 422.
        self.assertEqual(luma_duration(5), '5s')
        self.assertEqual(luma_duration(7), '5s')
        self.assertEqual(luma_duration(8), '10s')
        self.assertEqual(luma_duration(12), '10s')
        self.assertNotIn(luma_duration(12), (8, 12, '12s'))

    def test_an_image_becomes_start_frame_not_the_retired_image_url(self):
        """Dropping it silently would turn image-to-video into text-to-video."""
        with mock.patch.object(
            self.service._session, 'post', return_value=_Response(201, {'id': 'gen_1'})
        ) as post:
            self.service.submit_video_generation(
                prompt='continue this', image_url='https://i/frame.png'
            )

        payload = post.call_args.kwargs['json']
        self.assertNotIn('image_url', payload)
        self.assertEqual(
            payload['video']['start_frame'],
            {'url': 'https://i/frame.png'},
        )

    def test_an_imageless_submit_does_not_send_start_frame(self):
        with mock.patch.object(
            self.service._session, 'post', return_value=_Response(201, {'id': 'gen_1'})
        ) as post:
            self.service.submit_video_generation(prompt='a mask')

        self.assertNotIn('start_frame', post.call_args.kwargs['json']['video'])

    # --- status classification -----------------------------------------

    def test_out_of_credits_advances_the_chain(self):
        """402 is the whole reason the fallback chain exists."""
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(
                402,
                {
                    'detail': 'Not enough credits to continue.',
                    'error': {'code': 'RATE_LIMIT.BUDGET.EXCEEDED'},
                },
            ),
        ):
            with self.assertRaises(ProviderUnavailable) as ctx:
                self.service.submit_video_generation(prompt='a mask')

        self.assertIn('402', str(ctx.exception))
        self.assertIn('Not enough credits', str(ctx.exception))

    def test_a_dead_or_wrong_key_advances_the_chain(self):
        for status in (401, 403):
            with self.subTest(status=status):
                with mock.patch.object(
                    self.service._session,
                    'post',
                    return_value=_Response(status, {'detail': 'Invalid API key'}),
                ):
                    with self.assertRaises(ProviderUnavailable):
                        self.service.submit_video_generation(prompt='a mask')

    def test_a_bad_request_stops_the_chain(self):
        """400 means this input is wrong; the next vendor would agree."""
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(400, {'detail': 'Unknown model: nope'}),
        ):
            with self.assertRaises(ProviderRejected) as ctx:
                self.service.submit_video_generation(prompt='a mask')

        self.assertNotIsInstance(ctx.exception, ProviderUnavailable)
        self.assertIn('Unknown model', str(ctx.exception))

    def test_a_validation_error_is_rendered_not_json_dumped(self):
        """Pydantic returns `detail` as a *list*; naive code ships raw JSON."""
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(
                422,
                {
                    'detail': [
                        {'msg': 'Field required', 'loc': ['body', 'prompt']},
                    ]
                },
            ),
        ):
            with self.assertRaises(ProviderRejected) as ctx:
                self.service.submit_video_generation(prompt='a mask')

        self.assertIn('Field required', str(ctx.exception))

    def test_a_rate_limit_is_unavailable_rather_than_a_rejection(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(429, {'detail': 'Too many requests'}),
        ):
            with self.assertRaises(ProviderUnavailable):
                self.service.submit_video_generation(prompt='a mask')

    # --- response parsing ----------------------------------------------

    def test_submit_returns_the_engine_that_served(self):
        with mock.patch.object(
            self.service._session,
            'post',
            return_value=_Response(201, {'id': 'gen_1', 'state': 'queued'}),
        ):
            result = self.service.submit_video_generation(prompt='a mask')

        self.assertEqual(result['id'], 'gen_1')
        self.assertEqual(result['status'], 'pending')
        self.assertEqual(result['provider'], 'luma')
        self.assertEqual(result['engine'], f'luma-{DEFAULT_LUMA_MODEL}')

    def test_the_agents_output_array_is_read_for_the_video_url(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(
                200,
                {
                    'state': 'completed',
                    'output': [{'type': 'video', 'url': 'https://cdn/out.mp4'}],
                },
            ),
        ):
            result = self.service.get_job_status('gen_1')

        self.assertEqual(result['video_url'], 'https://cdn/out.mp4')

    def test_processing_maps_to_the_status_the_view_already_branches_on(self):
        for state, expected in (
            ('queued', 'pending'),
            ('processing', 'in_progress'),
            ('completed', 'completed'),
            ('failed', 'failed'),
        ):
            with self.subTest(state=state):
                with mock.patch.object(
                    self.service._session,
                    'get',
                    return_value=_Response(200, {'state': state}),
                ):
                    result = self.service.get_job_status('gen_1')
                self.assertEqual(result['status'], expected)

    def test_a_failed_generation_reports_the_moderators_reason(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(
                200,
                {'state': 'failed', 'failure_reason': 'Prompt was rejected'},
            ),
        ):
            result = self.service.get_job_status('gen_1')

        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['error'], 'Prompt was rejected')

    def test_a_failure_code_without_a_reason_is_still_readable(self):
        with mock.patch.object(
            self.service._session,
            'get',
            return_value=_Response(
                200, {'state': 'failed', 'failure_code': 'content_moderated'}
            ),
        ):
            result = self.service.get_job_status('gen_1')

        self.assertEqual(result['error'], 'Generation failed (content_moderated)')

    def test_progress_is_normalised_from_both_scales(self):
        """Luma has reported 0..1 and 0..100 across API versions."""
        for raw, expected in ((0.42, 42), (42, 42), (None, 50)):
            with self.subTest(raw=raw):
                with mock.patch.object(
                    self.service._session,
                    'get',
                    return_value=_Response(
                        200, {'state': 'processing', 'progress': raw}
                    ),
                ):
                    result = self.service.get_job_status('gen_1')
                self.assertEqual(result['progress'], expected)


class NormaliseProgressTests(SimpleTestCase):
    def test_fraction_and_percentage_both_normalise(self):
        self.assertEqual(_normalise_progress(0.5, 'in_progress'), 50)
        self.assertEqual(_normalise_progress(50, 'in_progress'), 50)

    def test_completed_is_always_100(self):
        self.assertEqual(_normalise_progress(0.1, 'completed'), 100)

    def test_non_numeric_does_not_crash(self):
        self.assertEqual(_normalise_progress('nope', 'in_progress'), 50)
        self.assertEqual(_normalise_progress(None, 'queued'), 0)

    def test_booleans_are_not_treated_as_numbers(self):
        # `isinstance(True, int)` is True in Python; progress must not be.
        self.assertEqual(_normalise_progress(True, 'in_progress'), 50)

    def test_out_of_range_is_clamped(self):
        self.assertEqual(_normalise_progress(150, 'in_progress'), 100)
        self.assertEqual(_normalise_progress(-5, 'in_progress'), 0)

    def test_the_agents_processing_state_still_moves_the_bar(self):
        self.assertEqual(_normalise_progress(None, 'processing'), 50)
