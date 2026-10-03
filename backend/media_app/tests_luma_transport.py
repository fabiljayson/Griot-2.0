"""The Luma AI client must not turn an upstream network fault into a 500.

Two distinct failure modes were unguarded:

* `submit_video_generation` only raised `LumaAIError` for an HTTP error status.
  A connect timeout, DNS failure or connection reset raised
  `requests.RequestException`, which the view does not catch — so a stalled
  network produced a 500 instead of the 502 the view already returns for other
  upstream failures, and the `VideoGenerationJob` row was left permanently
  PENDING with no recorded reason.
* `get_job_status` had no guard at all. It is called on every poll of
  `/api/videos/{id}/status/`; a transport error there broke the client's poll
  loop and discarded the progress already recorded, even though the render was
  still running on Luma's side.

The polling path is the important one: it must degrade to "still in progress",
never to an error.
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

TIMEOUT = requests.exceptions.ConnectTimeout('connection timed out')


class _Response:
    def __init__(self, status_code=200, payload=None, text=''):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self):
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

    def test_cancel_reports_a_transport_error_instead_of_raising(self):
        with mock.patch.object(
            self.service._session, 'delete', side_effect=TIMEOUT
        ):
            result = self.service.cancel_job('luma_abc')

        self.assertIn('error', result)
        self.assertNotIn('status', result)

    def test_cancel_happy_path_still_works(self):
        with mock.patch.object(
            self.service._session, 'delete', return_value=_Response(200)
        ):
            result = self.service.cancel_job('luma_abc')

        self.assertEqual(result['status'], 'cancelled')

    # --- transport configuration ---------------------------------------

    def test_session_has_an_explicit_timeout(self):
        """Without this, a stalled Luma socket pins a worker indefinitely."""
        self.assertIsNotNone(self.service._session.timeout)
        connect, read = self.service._session.timeout
        self.assertGreater(connect, 0)
        self.assertGreater(read, 0)

    def test_api_base_is_https(self):
        self.assertTrue(LUMA_API_BASE.startswith('https://'))


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
