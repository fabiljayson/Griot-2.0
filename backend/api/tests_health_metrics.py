"""Regression tests for the unauthenticated /api/health/metrics/ endpoint.

The endpoint returns six `count()` queries to an anonymous caller. That is
acceptable; returning *exact* totals from it is not. Exact counts combined with
the public story/artifact lists disclose sign-up growth, total scan volume, and
— because `users` is not otherwise public — roughly how many accounts exist.
It also gives an anonymous caller a repeatable counting oracle.

The fix rounds every count up to the next power of two, so a monitor still sees
the order of magnitude and the numbers cannot be differenced to recover an
exact total.
"""

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from api.views import _banded_count

User = get_user_model()

METRICS_URL = '/api/health/metrics/'


class BandedCountTests(TestCase):
    """The banding function itself — pure, so it is cheap to pin exactly."""

    def test_zero_stays_zero(self):
        self.assertEqual(_banded_count(0), 0)

    def test_exact_powers_of_two_are_unchanged(self):
        for value in (1, 2, 4, 8, 16, 1024):
            self.assertEqual(_banded_count(value), value)

    def test_rounds_up_to_the_next_power_of_two(self):
        self.assertEqual(_banded_count(3), 4)
        self.assertEqual(_banded_count(5), 8)
        self.assertEqual(_banded_count(1000), 1024)
        self.assertEqual(_banded_count(4821), 8192)

    def test_never_under_reports(self):
        """Rounding down would let subtraction recover the true total."""
        for value in range(1, 300):
            self.assertGreaterEqual(_banded_count(value), value)

    def test_banding_is_not_reversible_by_differencing(self):
        """Two different true counts can land on the same band."""
        self.assertEqual(_banded_count(4821), _banded_count(4822))
        self.assertEqual(_banded_count(100), _banded_count(127))

    def test_bands_have_usable_resolution_for_monitoring(self):
        """Not so coarse that growth is invisible between bands.

        Power-of-two banding has a worst case just under 2x — that is inherent
        to the scheme and is the price of not publishing an exact total. The
        bound is asserted so a future change to a coarser scheme (4x, 10x) is
        caught.
        """
        for value in (10, 100, 1000, 10000):
            self.assertLess(_banded_count(value) / value, 2.0)


@override_settings(ROOT_URLCONF='config.urls')
class HealthMetricsDisclosureTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_counts_are_banded_not_exact(self):
        for index in range(5):
            User.objects.create_user(
                f'user{index}', email=f'user{index}@example.com', password='x'
            )

        resp = self.client.get(METRICS_URL)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data['counts']['users'], 8)  # not 5

    def test_empty_instance_reports_zero(self):
        resp = self.client.get(METRICS_URL)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data['counts']['users'], 0)

    def test_process_gauges_are_still_exact(self):
        """Uptime and request count are not business data.

        Banding those would break the monitors that consume them, and they
        reveal nothing about the data set.
        """
        resp = self.client.get(METRICS_URL)
        self.assertIn('uptime_seconds', resp.data['process'])
        self.assertIn('requests_served', resp.data['process'])
        self.assertIsInstance(resp.data['process']['uptime_seconds'], float)

    def test_endpoint_stays_unauthenticated_for_monitors(self):
        """The fix must not break the load balancer it was written for."""
        resp = self.client.get(METRICS_URL)
        self.assertEqual(resp.status_code, 200)

    def test_health_and_ready_are_unaffected(self):
        self.assertEqual(self.client.get('/api/health/').status_code, 200)
        self.assertEqual(self.client.get('/api/health/ready/').status_code, 200)
