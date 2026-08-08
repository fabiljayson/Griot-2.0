"""Tests for Phase 10 observability: health probes, metrics, and logging."""

import json
import logging

from django.contrib.auth import get_user_model
from django.test import SimpleTestCase
from rest_framework import status
from rest_framework.test import APITestCase

from api.logging import JsonFormatter
from stories.models import Story

User = get_user_model()


class HealthProbeTests(APITestCase):
    """Liveness / readiness / metrics endpoints."""

    def test_liveness_probe(self):
        resp = self.client.get('/api/health/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ok')
        self.assertEqual(resp.data['service'], 'griot-2.0-backend')

    def test_readiness_probe_with_database(self):
        resp = self.client.get('/api/health/ready/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ok')
        self.assertEqual(resp.data['database'], 'ok')

    def test_metrics_endpoint_structure(self):
        resp = self.client.get('/api/health/metrics/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('process', resp.data)
        self.assertIn('uptime_seconds', resp.data['process'])
        self.assertIn('requests_served', resp.data['process'])
        self.assertIn('counts', resp.data)
        for key in (
            'users',
            'published_stories',
            'artifacts',
            'qr_scans',
            'quiz_attempts',
            'badges_earned',
        ):
            self.assertIn(key, resp.data['counts'])

    def test_metrics_counts_reflect_data(self):
        contributor = User.objects.create_user(
            'contrib1', email='c@test.com', password='pass123', role='contributor'
        )
        Story.objects.create(
            title='Published Tale',
            content='A published story.',
            author=contributor,
            status=Story.Status.PUBLISHED,
        )

        resp = self.client.get('/api/health/metrics/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(resp.data['counts']['users'], 1)
        self.assertEqual(resp.data['counts']['published_stories'], 1)


class RequestLoggingTests(APITestCase):
    """The request middleware emits one structured log line per request."""

    def test_request_is_logged(self):
        with self.assertLogs('api.request', level='INFO') as logs:
            self.client.get('/api/health/')

        self.assertTrue(
            any('http_request' in line for line in logs.output),
            'expected a request log line, got: %s' % logs.output,
        )
        # The LogRecord carries method/path/status metadata via extra kwargs.
        # (assertLogs renders its own default-formatted output lines, so the
        # structured fields are asserted on the captured records instead.)
        request_records = [r for r in logs.records if r.getMessage() == 'http_request']
        self.assertTrue(request_records, 'expected a request log record')
        record = request_records[-1]
        self.assertEqual(record.method, 'GET')
        self.assertEqual(record.path, '/api/health/')
        self.assertEqual(record.status, 200)

    def test_request_log_attributes_jwt_user(self):
        """The JWT username is resolved in middleware (DRF auth runs later)."""
        User.objects.create_user(
            'loguser', email='log@test.com', password='pass123'
        )
        token_resp = self.client.post(
            '/api/auth/token/',
            {'username': 'loguser', 'password': 'pass123'},
            format='json',
        )
        self.assertEqual(token_resp.status_code, status.HTTP_200_OK)
        token = token_resp.data['access']

        with self.assertLogs('api.request', level='INFO') as logs:
            self.client.get(
                '/api/health/',
                HTTP_AUTHORIZATION=f'Bearer {token}',
            )

        request_records = [r for r in logs.records if r.getMessage() == 'http_request']
        self.assertEqual(request_records[-1].user, 'loguser')


class JsonFormatterTests(SimpleTestCase):
    """The structured formatter emits single-line JSON with extra metadata."""

    def test_format_merges_extra_kwargs(self):
        record = logging.LogRecord(
            'api.request',
            logging.INFO,
            'api/middleware.py',
            1,
            'http_request',
            None,
            None,
        )
        record.method = 'GET'
        record.path = '/api/health/'
        record.status = 200

        parsed = json.loads(JsonFormatter().format(record))

        self.assertEqual(parsed['level'], 'INFO')
        self.assertEqual(parsed['logger'], 'api.request')
        self.assertEqual(parsed['message'], 'http_request')
        self.assertEqual(parsed['method'], 'GET')
        self.assertEqual(parsed['status'], 200)
        self.assertIn('timestamp', parsed)
