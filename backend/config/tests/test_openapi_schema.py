"""The published OpenAPI schema must generate cleanly.

drf-spectacular reports problems as warnings and errors on stderr and still
writes a schema either way, so a regression here is easy to miss: the file
keeps generating, the endpoints just quietly drop out of it or appear with the
wrong types. That is what happened — the schema had 48 issues, including
`/api/users/me/`, all seven admin analytics endpoints, both media viewsets and
the deep-link lookup being absent entirely, and every integer primary key
documented as a string.

This asserts the *count* is zero, which is the only form of the check that is
useful: enumerating the individual warnings would rot as soon as one is fixed
and would not catch a new one appearing.

Run with:

    DJANGO_SETTINGS_MODULE=config.settings.test python manage.py test \
        config.tests.test_openapi_schema
"""

import io
from contextlib import redirect_stderr

from django.test import SimpleTestCase

from drf_spectacular.generators import SchemaGenerator


class OpenAPISchemaTests(SimpleTestCase):
    """The schema is generated once and asserted on from several angles."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.stderr = io.StringIO()
        with redirect_stderr(cls.stderr):
            cls.schema = SchemaGenerator().get_schema(
                request=None, public=True,
            )
        cls.output = cls.stderr.getvalue()
        cls.stderr.close()

    def test_schema_generates_with_no_warnings_or_errors(self):
        # The specific phrasing comes from drf-spectacular's own summary
        # line, which is the aggregate of everything else it complained about.
        self.assertNotIn(
            'Warnings:', self.output,
            f'drf-spectacular reported warnings:\n{self.output}',
        )
        self.assertNotIn(
            'Errors:', self.output,
            f'drf-spectacular reported errors:\n{self.output}',
        )

    def test_integer_primary_keys_are_documented_as_integers(self):
        """A viewset with an AutoField pk must not publish the id as a string."""
        operation = self.schema['paths']['/api/media/videos/{id}/']['get']
        parameters = {
            parameter['name']: parameter for parameter in operation['parameters']
        }
        self.assertIn('id', parameters)
        self.assertEqual(parameters['id']['schema']['type'], 'integer')

    def test_health_endpoints_are_present(self):
        """These are what uptime monitors and the Flutter client poll."""
        for path in ('/api/health/', '/api/health/ready/', '/api/health/metrics/'):
            self.assertIn(path, self.schema['paths'])

    def test_me_endpoint_is_present(self):
        """/api/users/me/ was silently missing — an APIView with no
        `serializer_class` is skipped by the generator."""
        paths = self.schema['paths']
        self.assertIn('/api/users/me/', paths)
        self.assertIn('get', paths['/api/users/me/'])
        self.assertIn('patch', paths['/api/users/me/'])
        self.assertIn('delete', paths['/api/users/me/'])

    def test_admin_analytics_endpoints_are_present(self):
        """Same cause as MeView: APIViews that built their serializer by hand
        without declaring it, so all seven were absent from the document."""
        paths = self.schema['paths']
        for path in (
            '/api/analytics/dashboard/',
            '/api/analytics/users/',
            '/api/analytics/users/list/',
            '/api/analytics/stories/',
            '/api/analytics/gamification/',
            '/api/analytics/qr-codes/',
            '/api/analytics/engagement/',
        ):
            self.assertIn(path, paths, f'{path} missing from the OpenAPI schema')