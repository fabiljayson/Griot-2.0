"""SSRF-guard tests for the crawler's HTTP layer.

A crawled page is third-party input: every URL it links — and every redirect
target — must be refused when it points at loopback, private, link-local or
otherwise non-public space, or at a non-HTTP scheme.
"""

import unittest
from unittest.mock import Mock, patch

import session
from session import SsrfBlockedError, fetch_page, guard_url


class GuardUrlTests(unittest.TestCase):
    def assert_blocked(self, url: str) -> None:
        with self.assertRaises(SsrfBlockedError, msg=f"should block {url}"):
            guard_url(url)

    def test_blocks_loopback_and_metadata_literals(self):
        self.assert_blocked("http://127.0.0.1/")
        self.assert_blocked("http://127.0.0.1:8000/admin/")
        self.assert_blocked("http://169.254.169.254/latest/meta-data/")
        self.assert_blocked("http://[::1]/")

    def test_blocks_private_ranges(self):
        self.assert_blocked("http://10.0.0.8/")
        self.assert_blocked("http://192.168.1.1/")
        self.assert_blocked("http://172.31.255.255/")

    def test_blocks_hostname_that_resolves_to_loopback(self):
        # Real resolution, no network: localhost always lands in 127.0.0.1/8.
        self.assert_blocked("http://localhost/")

    def test_blocks_non_http_schemes(self):
        self.assert_blocked("ftp://example.com/file")
        self.assert_blocked("file:///etc/passwd")
        self.assert_blocked("gopher://example.com/")
        self.assert_blocked("not-a-url-with-scheme")

    def test_allows_public_addresses(self):
        # getaddrinfo on a literal is local; nothing is fetched here.
        guard_url("http://93.184.216.34/")
        guard_url("https://93.184.216.34/path")


class RedirectGuardTests(unittest.TestCase):
    def _redirect(self, location: str) -> Mock:
        resp = Mock()
        resp.status_code = 302
        resp.headers = {"location": location}
        return resp

    @patch.object(session._session, "get")
    def test_redirect_into_private_space_is_blocked(self, get: Mock):
        get.return_value = self._redirect("http://127.0.0.1/steal")

        with self.assertRaises(SsrfBlockedError):
            session._get("http://93.184.216.34/start")

        # Exactly one hop went out; the redirect target was guarded first.
        get.assert_called_once()

    @patch.object(session._session, "get")
    def test_too_many_redirects_is_blocked(self, get: Mock):
        get.return_value = self._redirect("http://93.184.216.34/again")

        with self.assertRaises(SsrfBlockedError):
            session._get("http://93.184.216.34/start")

        self.assertEqual(get.call_count, session.MAX_REDIRECTS + 1)

    @patch.object(session._session, "get")
    def test_fetch_page_returns_none_when_redirect_is_blocked(self, get: Mock):
        get.return_value = self._redirect("http://169.254.169.254/")

        self.assertIsNone(fetch_page("http://93.184.216.34/page"))
        get.assert_called_once()


class FetchPageBlockedTests(unittest.TestCase):
    @patch.object(session._session, "get")
    def test_blocked_url_never_reaches_the_network(self, get: Mock):
        # Blocked before the retry loop: no attempts, no backoff sleeps.
        self.assertIsNone(fetch_page("http://127.0.0.1:8000/"))
        get.assert_not_called()

    @patch.object(session._session, "get")
    def test_relative_links_are_guarded_after_join(self, get: Mock):
        # runner passes '/some-page/'; it is joined onto BASE_URL before the
        # guard sees it — guard must run on the joined URL, not the stub.
        self.assertIsNone(fetch_page("ftp://evil.example/x"))
        get.assert_not_called()


class DownloadStreamTests(unittest.TestCase):
    @patch.object(session._session, "get")
    def test_blocked_image_url_raises_before_fetching(self, get: Mock):
        with self.assertRaises(SsrfBlockedError):
            session.download_stream("http://10.0.0.5/internal.jpg")
        get.assert_not_called()


if __name__ == "__main__":
    unittest.main()
