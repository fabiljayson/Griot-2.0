"""The MEDIA_URL route is registered explicitly, so pin what it guarantees.

`config/urls.py` mounts `django.views.static.serve` at MEDIA_URL because
Django's own `static()` helper no-ops when DEBUG is False and Render's free
tier has neither a persistent disk nor a media service. That is a deliberate
trade-off, and the trade-off has a security half that deserves a test rather
than a comment: `serve` is documented as "not hardened for production use", so
the property worth pinning is that it cannot be walked out of MEDIA_ROOT.

These tests are also the tripwire for the documented exit from this design. If
a real disk or a CDN is ever put in front of the app and this block is deleted
from `config/urls.py`, `test_media_route_is_registered` fails — which is the
signal to delete this file too, rather than leave a test asserting behaviour
nobody has any more.
"""

import sys
import tempfile
from pathlib import Path

from django.test import Client, SimpleTestCase, override_settings
from django.urls import resolve, reverse


class MediaRouteRegistrationTests(SimpleTestCase):
    def test_media_route_is_registered(self):
        """The route exists in production settings, not just under DEBUG."""
        match = resolve('/media/stories/covers/example.jpg')
        self.assertEqual(match.url_name, 'media')

    def test_media_url_is_reversible(self):
        self.assertEqual(reverse('media', args=['stories/covers/a.jpg']),
                         '/media/stories/covers/a.jpg')


class MediaServingTests(SimpleTestCase):
    """What the route actually does with a request."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / 'stories' / 'covers').mkdir(parents=True)
        (self.root / 'stories' / 'covers' / 'a.jpg').write_bytes(b'jpeg-bytes')
        # A secret that lives *outside* MEDIA_ROOT, next to it on disk.
        self.secret = self.root.parent / 'secret.txt'
        self.secret.write_text('do not serve me')
        self.addCleanup(self.secret.unlink)

        self.client = Client()

    def _get(self, path):
        # ROOT_URLCONF points at a module that re-reads MEDIA_ROOT on import;
        # see config/tests/media_urls.py for why that indirection is needed.
        # The module has to be evicted from sys.modules each time as well:
        # Python caches imports for the life of the process, so the second
        # test in this class would otherwise keep serving the *first* test's
        # temporary directory.
        sys.modules.pop('config.tests.media_urls', None)
        with override_settings(
            MEDIA_ROOT=self.root,
            ROOT_URLCONF='config.tests.media_urls',
        ):
            try:
                return self.client.get(path)
            finally:
                sys.modules.pop('config.tests.media_urls', None)

    @staticmethod
    def _body(resp):
        """Read a response body, streamed or not.

        A served file comes back as a `FileResponse` (no `.content`); a
        rejected path comes back as a plain `HttpResponseBadRequest` (no
        `.streaming_content`).
        """
        if hasattr(resp, 'streaming_content'):
            return b''.join(resp.streaming_content)
        return resp.content

    def test_serves_a_file_under_media_root(self):
        resp = self._get('/media/stories/covers/a.jpg')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self._body(resp), b'jpeg-bytes')

    def test_missing_file_is_404(self):
        self.assertEqual(
            self._get('/media/stories/covers/nope.jpg').status_code, 404,
        )

    def test_traversal_above_media_root_is_refused(self):
        # The whole reason this file exists. `serve` normalises the path and
        # must not be talked into reading a sibling of MEDIA_ROOT.
        for attempt in (
            '/media/../secret.txt',
            '/media/../../etc/passwd',
            '/media/stories/../../secret.txt',
            '/media/./../secret.txt',
        ):
            with self.subTest(attempt=attempt):
                resp = self._get(attempt)
                # `serve` normalises the path and rejects anything escaping the
                # root outright (400), rather than 404-ing or — worse —
                # serving the file.
                self.assertNotEqual(resp.status_code, 200)
                self.assertNotIn(b'do not serve me', self._body(resp))

    def test_absolute_path_is_not_treated_as_a_filename(self):
        resp = self._get('/media//etc/passwd')
        self.assertNotEqual(resp.status_code, 200)
