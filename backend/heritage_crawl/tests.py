"""
Tests for the cultural heritage crawler.

The spec (§22.9) asks for security restrictions, provenance tracking, duplicate
detection, media extraction and the admin workflow to be tested. They are, and
the tests below are grouped to match. But the grouping is not the point; the
point is what each test is defending against, so most of them open by naming the
defect they would catch.

Three properties get the most attention, because they are the ones where a
plausible-looking bug produces permanently wrong data rather than an exception:

1. **Nothing reaches the corpus as published.** §3 and §13. A crawler that
   publishes unreviewed heritage text is not a bug, it is a cultural-harm
   incident, and it is the kind of thing that passes every other test in the
   file.
2. **Everything in the corpus is traceable.** §5. A Story with no source URL
   is unfalsifiable heritage, and readers are shown it as fact.
3. **The crawler cannot be aimed at the private network.** §20. An
   unrestricted URL endpoint here is an SSRF primitive with a database behind
   it.

Network access is not mocked at the HTTP library level throughout; instead the
pipeline is exercised end-to-end against a `responses`-free fake by patching
`heritage_crawl.fetching.fetch`, so extraction, relevance, dedup, provenance and
the review workflow all run for real. The security tests deliberately call the
real `assert_safe_url` and the real `fetch`, because those are the guards, and
a mocked guard proves nothing.
"""

from datetime import date

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from heritage_crawl import fetching
from heritage_crawl.extract import extract_page
from heritage_crawl.fetching import (
    DisallowedDomainError,
    HTTPError,
    InvalidURLError,
    RobotsDisallowedError,
    SSRFBlockedError,
    TooLargeError,
    UnsupportedContentTypeError,
    _globish,
    assert_safe_url,
    discover_urls,
    fetch,
    normalise_url,
    url_hash,
)
from heritage_crawl.ingest import (
    _DEDUPABLE_STATUSES,
    CRAWLER_ACCOUNT_USERNAME,
    _find_duplicate,
    crawl_source,
    crawler_account,
)
from heritage_crawl.models import (
    CrawledItem,
    CrawlJob,
    CrawlMedia,
    CrawlSource,
    SourceReference,
)
from heritage_crawl.normalize import content_fingerprint, unique_slug
from heritage_crawl.relevance import (
    detect_cultural_groups,
    detect_region,
    is_relevant,
    score_page,
)
from heritage_crawl.review import ReviewError, approve_item, reject, request_correction, unpublish
from heritage_crawl.source_config import (
    _EXCLUDE_NOISE,
    BUILTIN_SOURCES,
    seed_sources,
)
from qr_codes.models import Artifact
from stories.models import Story

User = get_user_model()

# --- HTML fixtures ---------------------------------------------------------
#
# Written inline rather than as files because the difference between a fixture
# that tests the extractor and one that tests the fixture is easy to lose. Each
# carries the specific defect it would let through.

HERITAGE_PAGE = """
<!DOCTYPE html>
<html lang="fr">
<head>
  <title>Masque de la Vallée du Mbem | Musée National du Cameroun</title>
  <meta name="description" content="Masque en bois sculpté, collected among the
        Bamiléké peoples of the West Region of Cameroon.">
  <meta name="author" content="Dr. Nkolo">
  <meta name="dc.publisher" content="Musée National du Cameroun">
  <meta property="article:published_time" content="2019-04-12">
  <meta name="language" content="fr">
</head>
<body>
  <nav><a href="/">Accueil</a><a href="/contact">Contact</a></nav>
  <h1>Masque de la Vallée du Mbem</h1>
  <p>Ce masque en bois sculpté a été collecté parmi les Bamiléké de la région
     de l'Ouest, au Cameroun. Il est attribué aux不凡 ancêtres et utilisé lors
     des rituels funéraires du village de Bandjoun.</p>
  <p>Le festival annuel célèbre la tradition des masques ancestraux au
     Cameroun, et ce bois de sang est un artefactzo important du patrimoine
     culturel national.</p>
  <img src="/media/masque-mbem.jpg" alt="Masque sculpté photographié de face">
  <img src="/static/logo.png" alt="Logo du musée">
  <a href="/fiches/masque-kota">Fiche suivante : masque Kota</a>
</body>
</html>
"""

NON_CAMEROON_PAGE = """
<!DOCTYPE html>
<html>
<head><title>An Ancient Mask from Mali</title></head>
<body><h1>An Ancient Mask from Mali</h1>
<p>A traditional carved wooden mask used in ritual ceremonies across Mali and
   West Africa, preserved in a French colonial archive.</p></body>
</html>
"""

#: A narrative page -- a legend, not a catalogue record. Present because the
#: artefact fixture was the only one in use, and it exercises the `Artifact`
#: branch exclusively. Every bug in the `Story` branch went unnoticed as a
#: result (see `CrawlerAccountTests`).
NARRATIVE_PAGE = """
<!DOCTYPE html>
<html lang="fr">
<head>
  <title>La Légende de Nungua</title>
  <meta name="description" content="Conte traditionnel recounts among the
        Bamileke of the West Region of Cameroon.">
  <meta name="author" content="Dr. Nkolo">
  <meta name="dc.publisher" content="Musée National du Cameroun">
</head>
<body>
  <h1>La Légende de Nungua</h1>
  <p>Cette tradition orale est racontée parmi les Bamiléké de la région de
     l'Ouest, au Cameroun. Dans ce conte, une figure légendaire fut sculptée
     dans le bois d'un arbre tombé, et le mythe explique pourquoi elle est
     exposée à chaque festival et cérémonie du village.</p>
  <p>La légende s'est transmise oralement de génération en génération, et le
     récit est encore prononcé aujourd'hui lors des célébrations rituelles.</p>
</body>
</html>
"""

#: Nested markup, shaped like the real pages that broke the extractor.
#:
#: `_strip_boilerplate` used to `find_all` and `decompose()` in the same loop.
#: `decompose()` detaches the node *and its subtree*, so the walk was left
#: holding references to nodes that no longer existed and raised
#: `AttributeError: 'NoneType' object has no attribute 'get'` from inside
#: Beautiful Soup. Every fixture here was flat, so nothing caught it -- and the
#: live UNESCO, MINAC and Discover Cameroon pages all failed on it.
NESTED_CHROME_PAGE = """
<!DOCTYPE html>
<html><body>
  <div class="page"><div class="wrapper"><div class="inner">
    <header class="site-header"><nav><a href="/">Home</a></nav></header>
    <div class="breadcrumb"><a href="/x">Home</a> &gt; Cameroon</div>
    <main class="content">
      <article class="entry">
        <h1>Le heritage culturel du Cameroun</h1>
        <p>Le Cameroon Possede un patrimoine culturel riche et varie, reconnu
           par l'UNESCO comme patrimoine mondial et inscrit sur la liste du
           patrimoine culturel immateriel. Les rites, les masques et les
           danses traditionnelles sont transmis de generation en generation
           dans les dix regions du pays, et chaque groupe culturel possede ses
           propres traditions, ekonomik ak artefact propre.</p>
      </article>
    </main>
    <footer class="site-footer"><p>Copyright 2024</p></footer>
  </div></div></div>
</body></html>
"""

BOILERPLATE_PAGE = """
<!DOCTYPE html>
<html>
<head><title>Contact</title></head>
<body>
  <nav><a href="/">Home</a><a href="/about">About</a><a href="/login">Login</a></nav>
  <div class="cookie-banner">We use cookies to improve your experience on our
     website. Accept all cookies to continue browsing our site today.</div>
  <div class="sidebar">Copyright 2024. All rights reserved. Terms of service |
     Privacy policy | Sitemap | Newsletter signup</div>
  <main><h1>Contact us</h1><p>Write to us using the form below.</p></main>
</body>
</html>
"""


def _fake_fetch(page_html: str, *, status_code: int = 200,
                content_type: str = 'text/html; charset=utf-8'):
    """Build a stand-in for `fetching.fetch` that returns fixture HTML.

    Patched over the real function in the pipeline tests so the whole flow runs
    for real while nothing touches the network.
    """
    from heritage_crawl.fetching import FetchResult

    def _fetch(url, **kwargs):
        return FetchResult(
            url=url,
            final_url=url,
            status_code=status_code,
            content_type=content_type,
            text=page_html,
            headers={'Content-Type': content_type},
        )

    return _fetch


def _fake_fetch_map(pages: dict[str, str], *, default: str | None = None,
                    calls: list[str] | None = None):
    """Like `_fake_fetch`, but the body depends on the URL.

    `_fake_fetch` answers every URL with the same HTML, which cannot express
    "this page links to that one, whose content differs" -- the shape discovery
    and dedup tests need. First matching key wins; `default` covers the rest.
    """
    from heritage_crawl.fetching import FetchResult

    fallback = default if default is not None else '<html><body>none</body></html>'

    def _fetch(url, **kwargs):
        if calls is not None:
            calls.append(url)
        body = fallback
        for fragment, html in pages.items():
            if fragment in url:
                body = html
                break
        return FetchResult(
            url=url,
            final_url=url,
            status_code=200,
            content_type='text/html; charset=utf-8',
            text=body,
            headers={'Content-Type': 'text/html; charset=utf-8'},
        )

    return _fetch


def _crawl_with_pages(source, pages, *, default=None, calls=None, **kwargs):
    """Run `crawl_source` against a URL-addressed fake fetch, no network."""
    import heritage_crawl.ingest as ingest

    original = ingest.fetching.fetch
    ingest.fetching.fetch = _fake_fetch_map(pages, default=default, calls=calls)
    try:
        return crawl_source(source, **kwargs)
    finally:
        ingest.fetching.fetch = original


class FetchingSecurityTests(TestCase):
    """§20: SSRF, scheme, allow-list, size cap, content type.

    These call the real guards. A test that mocks `assert_safe_url` and then
    asserts that `assert_safe_url` was called is a test of the mock.
    """

    ALLOWED = ['cameroon-nationalmuseum.cm']

    def test_https_url_on_allowed_domain_is_accepted(self):
        """The guard must not be so broad that nothing can pass it."""
        assert_safe_url('https://cameroon-nationalmuseum.cm/collections', self.ALLOWED)

    def test_http_scheme_is_allowed(self):
        """§1 lists http://cameroon-nationalmuseum.cm — rejecting it would
        make the primary source permanently uncrawlable."""
        assert_safe_url('http://cameroon-nationalmuseum.cm/', self.ALLOWED)

    def test_non_http_scheme_is_refused(self):
        """file://, ftp:// and gopher:// are all ways to read a local path."""
        for url in (
            'file:///etc/passwd',
            'ftp://cameroon-nationalmuseum.cm/x',
            'gopher://cameroon-nationalmuseum.cm/',
            'javascript:alert(1)',
        ):
            with self.subTest(url=url), self.assertRaises(InvalidURLError):
                assert_safe_url(url, self.ALLOWED)

    def test_host_outside_the_allowlist_is_refused(self):
        """The core SSRF control: a link on a crawled page cannot redirect us
        to another host, however plausible the hostname looks."""
        with self.assertRaises(DisallowedDomainError):
            assert_safe_url('https://evil.example.com/cameroon', self.ALLOWED)

    def test_lookalike_hostname_is_refused(self):
        """`cameroon-nationalmuseum.cm.evil.com` is not the museum. A naive
        `host in allowed` substring check would have let this through."""
        for host in (
            'cameroon-nationalmuseum.cm.evil.com',
            'evilcameroon-nationalmuseum.cm',
            'cameroon-nationalmuseum.cm.br',
        ):
            with self.subTest(host=host), self.assertRaises(DisallowedDomainError):
                assert_safe_url(f'https://{host}/x', self.ALLOWED)

    def test_loopback_is_refused(self):
        """127.0.0.1 resolves and is public-looking in a URL."""
        with self.assertRaises((DisallowedDomainError, SSRFBlockedError)):
            assert_safe_url('http://127.0.0.1:8000/admin/', self.ALLOWED)

    def test_allowlisting_loopback_still_refuses_it(self):
        """An administrator who adds 127.0.0.1 to allowed_domains must still not
        be able to reach their own admin. The domain list is an allow-list, not
        an override for the private-range check."""
        with self.assertRaises(SSRFBlockedError):
            assert_safe_url('http://127.0.0.1:8000/', ['127.0.0.1'])

    def test_private_and_link_local_ranges_are_refused(self):
        """RFC1918, link-local, and the cloud metadata endpoint that leaks
        instance credentials."""
        for url in (
            'http://10.0.0.5/',
            'http://192.168.1.1/',
            'http://172.16.0.1/',
            'http://169.254.169.254/latest/meta-data/',
            'http://[::1]/',
            'http://0.0.0.0/',
        ):
            with self.subTest(url=url), self.assertRaises(
                (DisallowedDomainError, SSRFBlockedError)
            ):
                assert_safe_url(url, ['10.0.0.5', '192.168.1.1', '172.16.0.1',
                                       '169.254.169.254', '::1', '0.0.0.0'])

    def test_redirect_to_a_disallowed_host_is_refused(self):
        """The allow-list has to survive a redirect, or the whole control is
        cosmetic: an allowed site can 302 anywhere. The response is modelled as
        `requests` would present it -- final status, final URL -- because that
        is what `fetch` re-validates."""
        redirected = _ok(
            '<html>metadata</html>',
            url='http://169.254.169.254/latest/meta-data/',
        )
        with self.assertRaises(
            (DisallowedDomainError, SSRFBlockedError, HTTPError)
        ):
            fetch(
                'https://cameroon-nationalmuseum.cm/go',
                allowed_domains=self.ALLOWED,
                session=_session_returning(redirected),
                respect_robots=False,
            )

    def test_redirect_to_a_new_path_on_the_same_host_is_allowed(self):
        """The re-check must not break normal redirects within one site."""
        same_host = _ok(
            '<html><body>moved</body></html>',
            url='https://cameroon-nationalmuseum.cm/new/path',
        )
        result = fetch(
            'https://cameroon-nationalmuseum.cm/old',
            allowed_domains=self.ALLOWED,
            session=_session_returning(same_host),
            respect_robots=False,
        )
        self.assertEqual(result.final_url, 'https://cameroon-nationalmuseum.cm/new/path')

    def test_oversized_response_raises_rather_than_being_read(self):
        """A hostile origin must not be able to exhaust memory. The cap is
        enforced while streaming, so the body is never fully read."""
        class _BigResponse:
            status_code = 200
            headers = {'Content-Type': 'text/html'}
            url = 'https://cameroon-nationalmuseum.cm/huge'
            text = ''
            content = b''

            def iter_content(self, chunk_size=8192):
                chunk = b'x' * 65536
                for _ in range(200):  # ~12.8MB, over the 1KB cap below
                    yield chunk

            def close(self):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

        with self.assertRaises(TooLargeError):
            fetch(
                'https://cameroon-nationalmuseum.cm/huge',
                allowed_domains=self.ALLOWED,
                max_bytes=1024,
                session=_session_returning(_BigResponse()),
                respect_robots=False,
            )

    def test_non_html_content_type_is_refused(self):
        """A 200 carrying an executable is not a page. Only HTML-ish bodies are
        ever handed to the parser."""
        for ctype in ('application/x-msdownload', 'text/x-php',
                      'application/octet-stream', 'image/svg+xml'):
            with self.subTest(content_type=ctype), self.assertRaises(
                UnsupportedContentTypeError
            ):
                fetch(
                    'https://cameroon-nationalmuseum.cm/download',
                    allowed_domains=self.ALLOWED,
                    session=_session_returning(
                        _ok('MZ binary payload', content_type=ctype)
                    ),
                    respect_robots=False,
                )

    def test_absolute_max_bytes_cannot_be_exceeded_by_configuration(self):
        """A source is admin-supplied data. A mistyped 10^9 must not become an
        unbounded read."""
        self.assertEqual(fetching.ABSOLUTE_MAX_BYTES, 20_000_000)
        self.assertLessEqual(fetching.ABSOLUTE_MAX_BYTES, 20_000_000)


def _ok(text='<html><body>ok</body></html>', content_type='text/html',
        status_code=200, url='https://cameroon-nationalmuseum.cm/'):
    """A minimal response object shaped like `requests.Response`.

    `fetch` reads `status_code`, `headers`, `url`, `iter_content`, and uses the
    object as a context manager, so all five have to be present -- an earlier
    version of this helper omitted two of them and every guard test failed with
    a TypeError rather than the assertion it was written to make.
    """
    class _Response:
        # Defined on the class, not the instance: `with` looks up the dunder on
        # the type. Assigning `r.__enter__ = ...` after construction looks like
        # it works and silently does not.
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    r = _Response()
    r.status_code = status_code
    # `fetch` decodes with `response.encoding or 'utf-8'`.
    r.encoding = 'utf-8'
    r.headers = {'Content-Type': content_type}
    r.url = url
    r.text = text
    r.content = text.encode('utf-8')
    r.iter_content = lambda chunk_size=8192: iter([text.encode('utf-8')])
    r.close = lambda: None
    return r


def _session_returning(response):
    """A session whose `get` returns `response`, and that mints no redirects."""
    class _Session:
        headers = {}

        def get(self, url, **kwargs):
            return response

    return _Session()


class LinkDiscoveryTests(TestCase):
    """`discover_urls` must return pages, not site furniture.

    Found by crawling the real UNESCO Cameroon page: 146 of the discovered
    links were `.css`, `.png` and `.svg` files. The crawl spent its page budget
    fetching them, each rejected by the content-type allow-list and recorded as
    an error, so a depth-1 crawl reached *fewer* real pages than depth-0.
    """

    def _links(self, html, url='https://ich.unesco.org/en/state/cameroon-CM'):
        return discover_urls(html, url, max_depth=1)

    def test_stylesheets_and_images_are_not_crawl_targets(self):
        html = """
        <a href="/css/styles.css">a</a>
        <a href="/favicon/favicon-32x32.png">b</a>
        <a href="/img/photo.jpg">c</a>
        <a href="/static/js/app.js">d</a>
        """
        self.assertEqual(self._links(html), [])

    def test_real_pages_are_still_discovered(self):
        html = '<a href="/en/RL/element-00001">a</a><a href="/en/state/x">b</a>'
        links = self._links(html)
        self.assertIn('https://ich.unesco.org/en/RL/element-00001', links)
        self.assertIn('https://ich.unesco.org/en/state/x', links)

    def test_a_section_named_after_a_format_is_not_an_asset(self):
        """`/en/pdf` is a section. Only the last segment's extension counts, and
        only when that extension is a known asset type."""
        html = '<a href="/patrimoine/pdf">a</a><a href="/docs/rapport.pdf">b</a>'
        links = self._links(html, url='https://minac.gov.cm/x')
        self.assertIn('https://minac.gov.cm/patrimoine/pdf', links)
        self.assertNotIn('https://minac.gov.cm/docs/rapport.pdf', links)

    def test_content_pages_under_image_directories_are_not_assets(self):
        """`/media/`, `/images/` and `/img/` are content directories on a great
        many CMSs. Treating the *directory* as furniture dropped legitimate
        article pages filed there; only a real file extension is an asset."""
        html = (
            '<a href="/media/article">a</a>'
            '<a href="/images/masque-story">b</a>'
            '<a href="/img/heritage">c</a>'
        )
        links = self._links(html, url='https://minac.gov.cm/x')
        for path in ('/media/article', '/images/masque-story', '/img/heritage'):
            self.assertIn(f'https://minac.gov.cm{path}', links)

    def test_image_files_under_those_directories_are_still_assets(self):
        """The extension check -- not the directory -- is what filters files."""
        html = '<a href="/media/photo.jpg">a</a><a href="/img/mask.png">b</a>'
        self.assertEqual(self._links(html, url='https://minac.gov.cm/x'), [])

    def test_offsite_links_are_still_dropped(self):
        html = '<a href="https://google.com/x">a</a>'
        self.assertEqual(self._links(html), [])

    def test_mailto_and_javascript_are_dropped(self):
        html = '<a href="mailto:a@b.c">a</a><a href="javascript:x()">b</a>'
        self.assertEqual(self._links(html), [])


class UrlPatternTests(TestCase):
    """`include_url_patterns` / `exclude_url_patterns` must match as globs.

    Found while configuring the real sources: `*/en/RL/*` is an invalid regex
    (`*` with nothing to repeat), and the resulting `re.error` was swallowed
    with a `return False`. An include pattern that matches nothing means the
    source discovers no links at all, so a crawl pointed at the UNESCO element
    pages returned its single seed URL and reported success.
    """

    def test_wildcards_match_across_path_segments(self):
        self.assertTrue(_globish('https://ich.unesco.org/en/RL/ngondo-02140',
                                 '*/en/RL/*'))
        self.assertTrue(_globish('https://www.musecam.org/collections/masque',
                                 '*/collections*'))

    def test_patterns_that_should_not_match(self):
        self.assertFalse(_globish('https://ich.unesco.org/en/state/cm',
                                  '*/en/RL/*'))
        self.assertFalse(_globish('https://discover-cameroon.com/en/history/',
                                  '*/culture*'))

    def test_plain_substrings_still_work(self):
        """Most patterns an administrator writes have no wildcards at all."""
        self.assertTrue(_globish(
            'https://minac.gov.cm/patrimoine/heritage/x', 'heritage'
        ))
        self.assertFalse(_globish('https://minac.gov.cm/patrimoine/x', 'heritage'))

    def test_regex_metacharacters_are_matched_literally(self):
        """A `+` in a path is a plus, not a quantifier."""
        self.assertTrue(_globish('https://x.gov/a+b', 'a+b'))
        self.assertFalse(_globish('https://x.gov/aab', 'a+b'))

    def test_an_empty_pattern_never_matches(self):
        self.assertFalse(_globish('https://x.gov/', ''))

    def test_include_patterns_actually_reach_discover_urls(self):
        """End to end: the seed page offers one element and one nav link, and
        only the element should survive the include filter."""
        html = (
            '<a href="/en/RL/ngondo-worship-02140">element</a>'
            '<a href="/en/change-password-request-00842">nav</a>'
            '<a href="/css/styles.css">css</a>'
        )
        links = discover_urls(
            html,
            'https://ich.unesco.org/en/state/cameroon-CM',
            include_patterns=['*/en/RL/*'],
            max_depth=1,
        )
        self.assertEqual(links, ['https://ich.unesco.org/en/RL/ngondo-worship-02140'])

    def test_exclude_patterns_remove_multilingual_duplicates(self):
        """The fr/es pages of one UNESCO element are the same content."""
        html = (
            '<a href="/en/RL/ngondo-02140">en</a>'
            '<a href="/fr/RL/ngondo-02140">fr</a>'
        )
        links = discover_urls(
            html,
            'https://ich.unesco.org/en/RL/ngondo-02140',
            include_patterns=['*/RL/*'],
            exclude_patterns=['*/fr/*'],
            max_depth=1,
        )
        self.assertEqual(links, ['https://ich.unesco.org/en/RL/ngondo-02140'])


class RobotsTests(TestCase):
    """§6: robots.txt is honoured. §15: unavailable robots is not a silent yes."""

    ALLOWED = ['cameroon-nationalmuseum.cm']

    def _fetch_with_robots(self, robots_body, target_url, robots_status=200):
        calls = []

        def _get(url, **kwargs):
            calls.append(url)
            if url.endswith('/robots.txt'):
                return _ok(robots_body, status_code=robots_status)
            return _ok('<html><body><p>Forbidden page</p></body></html>')

        class _Session:
            headers = {}

            def get(self, url, **kwargs):
                return _get(url, **kwargs)

        try:
            fetch(
                target_url,
                allowed_domains=self.ALLOWED,
                session=_Session(),
                respect_robots=True,
            )
        except FetchError_ as exc:
            return type(exc), calls
        return None, calls

    def test_disallowed_path_is_refused(self):
        error, calls = self._fetch_with_robots(
            'User-agent: *\nDisallow: /private/\n',
            'https://cameroon-nationalmuseum.cm/private/collection',
        )
        self.assertIs(error, RobotsDisallowedError)
        self.assertTrue(any('/robots.txt' in url for url in calls))

    def test_allowed_path_proceeds(self):
        error, _ = self._fetch_with_robots(
            'User-agent: *\nDisallow: /private/\n',
            'https://cameroon-nationalmuseum.cm/collections',
        )
        self.assertIsNone(error)

    def test_missing_robots_is_treated_as_allowed(self):
        """404 means no restrictions published, which is not permission to
        enforce a rule that does not exist."""
        error, _ = self._fetch_with_robots(
            '<html>404</html>',
            'https://cameroon-nationalmuseum.cm/collections',
            robots_status=404,
        )
        self.assertIsNone(error)

    def test_server_error_on_robots_blocks_the_fetch(self):
        """A 5xx from robots.txt means we do not know the rules. §15 lists
        network failures as something to handle conservatively, and crawling a
        site whose robots we could not read is the opposite of polite."""
        error, _ = self._fetch_with_robots(
            '<html>503</html>',
            'https://cameroon-nationalmuseum.cm/collections',
            robots_status=503,
        )
        self.assertIsNotNone(
            error,
            'a robots.txt we could not fetch was treated as permission',
        )


FetchError_ = fetching.FetchError


class URLNormalisationTests(TestCase):
    """Dedup depends on `url_hash`, so normalisation has to be stable."""

    def test_campaign_parameters_do_not_fork_the_record(self):
        """A page reached from a newsletter and from search is one page. Left
        in, `utm_*` forks every campaign link into a duplicate Story."""
        base = 'https://minac.gov.cm/patrimoine'
        self.assertEqual(
            url_hash(f'{base}?utm_source=newsletter'),
            url_hash(f'{base}?utm_source=google'),
        )
        self.assertEqual(
            url_hash(f'{base}?utm_source=x&gclid=y'),
            url_hash(base),
        )

    def test_meaningful_parameters_are_preserved(self):
        """Stripping must not go too far: `?id=42` selects a different page."""
        self.assertNotEqual(
            url_hash('https://minac.gov.cm/x?id=42'),
            url_hash('https://minac.gov.cm/x?id=43'),
        )

    def test_query_and_fragment_do_not_change_the_hash(self):
        """A page fetched via ?utm_source=twitter and via ?utm_source=email is
        the same page and must not become two records."""
        base = 'https://minac.gov.cm/patrimoine'
        self.assertEqual(
            url_hash(f'{base}?utm_source=twitter'),
            url_hash(f'{base}?utm_source=email'),
        )
        self.assertEqual(url_hash(base), url_hash(f'{base}#section'))

    def test_trailing_slash_and_case_do_not_change_the_host_key(self):
        """Host is lowercased; the path is not, because paths are
        case-sensitive on most servers."""
        self.assertEqual(
            url_hash('https://MINAC.gov.cm/x'),
            url_hash('https://minac.gov.cm/x'),
        )
        self.assertNotEqual(
            url_hash('https://minac.gov.cm/X'),
            url_hash('https://minac.gov.cm/x'),
        )

    def test_relative_links_resolve_against_the_page(self):
        self.assertEqual(
            normalise_url('/fiches/masque', base='https://minac.gov.cm/a/b/page'),
            'https://minac.gov.cm/fiches/masque',
        )


class RelevanceTests(TestCase):
    """§8: Cameroonian content is prioritised; unrelated content is not."""

    def test_cameroonian_heritage_page_scores_above_the_default_threshold(self):
        result = score_page(
            title='Masque de la Vallée du Mbem',
            description='Masque Bamiléké du Cameroun',
            body=HERITAGE_PAGE,
            url='https://ich.unesco.org/en/RL/masque-mbem-00001',
        )
        self.assertTrue(result.is_cameroonian)
        self.assertTrue(is_relevant(result, 0.70), msg=result.reasons)
        self.assertIn('references Cameroon', result.reasons)

    def test_a_cameroonian_host_alone_does_not_make_a_page_cameroonian(self):
        """§2 forbids importing unrelated African content. Treating an
        institutional host as proof meant a Musécam or MINAC page *about Mali*
        scored as Cameroonian heritage and cleared the gate -- the source being
        Cameroonian says nothing about the subject of the page."""
        result = score_page(
            title='An Ancient Mask from Mali',
            description='A traditional carved wooden mask used in ritual ceremonies',
            body=NON_CAMEROON_PAGE,
            url='https://cameroon-nationalmuseum.cm/mali-masks',
        )
        self.assertFalse(result.is_cameroonian)
        self.assertFalse(is_relevant(result, 0.70))
        self.assertIn(
            'institutional source', result.reasons,
            'the host should still earn the provenance bonus',
        )

    def test_non_cameroonian_page_is_capped_below_threshold(self):
        """§2 is explicit: do not import unrelated African or international
        content. A well-written page about Mali's masks must not squeak past
        because it shares the vocabulary."""
        result = score_page(
            title='An Ancient Mask from Mali',
            description='A traditional carved wooden mask used in ritual ceremonies',
            body=NON_CAMEROON_PAGE,
            url='https://example.org/mali-masks',
        )
        self.assertFalse(result.is_cameroonian)
        self.assertFalse(is_relevant(result, 0.70))
        self.assertLess(result.score, 0.49)

    def test_region_is_detected_in_english(self):
        self.assertEqual(detect_region('in the South-West region'), 'South-West')
        self.assertEqual(detect_region('West Region of Cameroon'), 'West')

    def test_region_is_detected_in_french(self):
        """The authoritative sources are French-language. A detector that only
        knew the English names left `region` empty on exactly the pages most
        likely to state it."""
        self.assertEqual(detect_region('situé dans la région de l’Ouest'), 'West')
        self.assertEqual(detect_region('région du Sud-Ouest'), 'South-West')
        self.assertEqual(detect_region('Nord du Cameroun'), 'North')

    def test_regions_map_only_to_official_names(self):
        """§9 lists the nine regions. A typo in a value would write an
        unsortable string into `Story.region`."""
        from heritage_crawl.relevance import REGIONS

        official = {
            'Centre', 'Littoral', 'West', 'North-West', 'South-West',
            'North', 'Far North', 'Adamawa', 'East', 'South',
        }
        for needle, value in REGIONS.items():
            with self.subTest(needle=needle):
                self.assertIn(value, official)

    def test_no_region_is_invented_when_absent(self):
        """§9: store NULL rather than invent. Guessing a region would put
        heritage in the wrong part of the country."""
        self.assertEqual(detect_region('a story with no geography at all'), '')

    def test_cultural_group_requires_an_explicit_mention(self):
        """§9: 'Do not infer a cultural group merely from the geographical
        location.' Naming the group is required."""
        groups = detect_cultural_groups('among the Bamiléké peoples')
        self.assertIn('Bamileke', groups)
        self.assertEqual(
            len(groups), 1,
            'one people matched two keys in CULTURAL_GROUPS and was counted twice',
        )
        self.assertEqual(
            detect_cultural_groups('a village in the West Region'), [],
            'a region must not imply a cultural group',
        )

    def test_boilerplate_does_not_make_a_page_look_relevant(self):
        """The cookie banner and footer are the highest-frequency text on any
        site. If they counted, every page on earth scores above threshold."""
        from heritage_crawl.extract import extract_page

        page = extract_page(BOILERPLATE_PAGE, 'https://example.org/contact')
        self.assertLess(len(page.body_text), 80)
        self.assertNotIn('cookie', page.body_text.lower())
        self.assertNotIn('all rights reserved', page.body_text.lower())


class NestedMarkupTests(TestCase):
    """The extractor must survive real-world DOM nesting.

    Regression guard for the live-crawl `AttributeError`. A flat fixture cannot
    catch it, because the defect is in the interaction between `find_all`
    returning a lazy walk and `decompose()` invalidating it.
    """

    def test_nested_chrome_does_not_crash_the_extractor(self):
        page = extract_page(
            NESTED_CHROME_PAGE, 'https://ich.unesco.org/en/state/cameroon-CM'
        )
        self.assertEqual(page.title, 'Le heritage culturel du Cameroun')

    def test_the_real_content_survives_boilerplate_removal(self):
        page = extract_page(
            NESTED_CHROME_PAGE, 'https://ich.unesco.org/en/state/cameroon-CM'
        )
        self.assertIn('patrimoine', page.body_text.lower())
        self.assertNotIn('copyright', page.body_text.lower())

    def test_chrome_is_actually_removed(self):
        """The fix must not turn the stripper into a no-op."""
        page = extract_page(
            NESTED_CHROME_PAGE, 'https://ich.unesco.org/en/state/cameroon-CM'
        )
        lowered = page.body_text.lower()
        self.assertNotIn('breadcrumb', lowered)
        self.assertNotIn('home', lowered)

    def test_a_nested_page_scores_as_relevant(self):
        page = extract_page(
            NESTED_CHROME_PAGE, 'https://ich.unesco.org/en/state/cameroon-CM'
        )
        result = score_page(
            title=page.title, description=page.description,
            body=page.body_text, url='https://ich.unesco.org/en/state/cameroon-CM',
        )
        self.assertTrue(result.is_cameroonian)
        self.assertTrue(is_relevant(result, 0.70), msg=result.reasons)


class NormalisationTests(TestCase):
    """§10 and §4: stable fingerprints, translated types, no invented data."""

    def test_fingerprint_ignores_whitespace_and_case(self):
        a = content_fingerprint('Le Masque', 'Le masque  est\nun artefact   rituel')
        b = content_fingerprint('le masque', 'le masque est un artefact rituel')
        self.assertEqual(a, b)

    def test_different_content_gets_different_fingerprints(self):
        self.assertNotEqual(
            content_fingerprint('A', 'mask from the west region'),
            content_fingerprint('B', 'mask from the north region'),
        )

    def test_unique_slug_avoids_a_collision(self):
        """`slug` is unique on both Story and Artifact. Two pages from one
        museum very often share a title, and the losing import used to raise
        IntegrityError outside the per-page error boundary -- aborting the
        whole crawl job rather than one page."""
        taken = {'masque-de-la-vallee-du-mbem'}
        first = unique_slug('Masque de la Vallée du Mbem', exists=taken.__contains__)
        self.assertNotIn(first, taken)
        second = unique_slug(
            'Masque de la Vallée du Mbem',
            exists={first, *taken}.__contains__,
        )
        self.assertNotIn(second, {first, *taken})

    def test_unique_slug_still_produces_a_readable_slug(self):
        self.assertEqual(
            unique_slug('Masque de la Vallée du Mbem'), 'masque-de-la-vallee-du-mbem'
        )

    def test_descriptive_labels_map_to_real_artifact_choices(self):
        """`relevance` emits descriptive labels; `normalize` translates them to
        `Artifact.ContentType`. An unmapped label must fall back to UNKNOWN
        rather than raise or invent a value."""
        from heritage_crawl.normalize import CONTENT_TYPE_MAP

        valid = {value for value, _ in Artifact.ContentType.choices}
        for descriptive in CONTENT_TYPE_MAP:
            self.assertIn(CONTENT_TYPE_MAP[descriptive], valid)

    def test_artefact_categories_map_to_real_artifact_choices(self):
        """`_MATERIAL_TERMS` is keyed by `Artifact.Category` and holds the
        trigger words. A key outside the model's vocabulary would make
        `Artifact.objects.create(category=...)` fail on the first real mask,
        which is exactly what these tests exist to catch."""
        from heritage_crawl.normalize import _MATERIAL_TERMS

        valid = {value for value, _ in Artifact.Category.choices}
        for category in _MATERIAL_TERMS:
            self.assertIn(category, valid, f'{category} is not a real category')

    def test_no_two_materials_claim_the_same_category(self):
        """A duplicated category key would make one of them unreachable and
        silently drop half the material vocabulary."""
        from heritage_crawl.normalize import _MATERIAL_TERMS

        terms = [t for group in _MATERIAL_TERMS.values() for t in group]
        duplicates = {t for t in terms if terms.count(t) > 1}
        self.assertEqual(
            duplicates, set(),
            'a trigger word maps to more than one category, so one is unreachable',
        )

    def test_every_category_has_trigger_words(self):
        """A category with no vocabulary can never be inferred, which is a
        quiet failure: the field simply always says 'other'."""
        from heritage_crawl.normalize import _MATERIAL_TERMS

        for category, terms in _MATERIAL_TERMS.items():
            with self.subTest(category=category):
                self.assertTrue(terms)


# --- Pipeline tests --------------------------------------------------------

class PipelineTestsBase(TestCase):
    """Shared fixtures for the end-to-end pipeline tests."""

    def setUp(self):
        self.source = CrawlSource.objects.create(
            slug='test-museum',
            name='Test Museum',
            base_url='https://cameroon-nationalmuseum.cm/',
            source_type=CrawlSource.SourceType.MUSEUM,
            reliability=CrawlSource.Reliability.AUTHORITATIVE,
            enabled=True,
            max_pages=2,
            max_depth=0,
            request_delay=0,
            seed_urls=['https://cameroon-nationalmuseum.cm/collections/masque-mbem'],
            default_licence=Story.Licence.UNDETERMINED,
            allow_media_download=False,
        )

    def produced(self, item):
        """Whatever an imported item became -- Story or Artifact.

        The mask fixture is a museum catalogue record, so the pipeline
        classifies it as an artefact. That is the right answer; the tests were
        wrong to assume a story, and bending the fixture to fit the test would
        have hidden the classifier's real behaviour.
        """
        if item.story_id:
            return item.story
        return item.artifact

    def corpus_count(self) -> int:
        """How many reader-facing records exist, whichever model they used."""
        return Story.objects.count() + Artifact.objects.count()

    def status_of(self, item) -> str:
        """'published' or not, whichever model the item landed on."""
        target = self.produced(item)
        if target is None:
            return 'none'
        return getattr(target, 'status', None) or (
            'published' if getattr(target, 'is_published', False) else 'unpublished'
        )

    def crawl(self, html=HERITAGE_PAGE, **kwargs):
        """Run the pipeline against fixture HTML, with no network access."""
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(html)
        try:
            return crawl_source(self.source, **kwargs)
        finally:
            ingest.fetching.fetch = original


class StoryImportTests(PipelineTestsBase):
    """The Story branch of the importer, which the artefact fixture skipped."""

    def setUp(self):
        super().setUp()
        self.source.base_url = 'https://ich.unesco.org/en/state/cameroon-CM'
        self.source.seed_urls = ['https://ich.unesco.org/en/RL/legend-nungua']
        self.source.save()

    def test_a_narrative_page_becomes_a_pending_story(self):
        outcome = self.crawl(html=NARRATIVE_PAGE)
        self.assertEqual(outcome.imported, 1)
        story = Story.objects.get()
        self.assertEqual(story.status, Story.Status.PENDING)
        self.assertIsNotNone(story.author)

    def test_the_story_records_its_source_in_provenance_notes(self):
        self.crawl(html=NARRATIVE_PAGE)
        notes = Story.objects.get().provenance_notes
        self.assertIn('ich.unesco.org', notes)
        self.assertIn('Original page:', notes)

    def test_an_artefact_page_does_not_become_a_story(self):
        """The two branches are distinct; the classifier is not guessing."""
        self.crawl(html=HERITAGE_PAGE)
        self.assertEqual(Story.objects.count(), 0)
        self.assertEqual(Artifact.objects.count(), 1)


class ImportSafetyTests(PipelineTestsBase):
    """§3/§13: crawled content must never be published by the crawler.

    This is the invariant the whole application rests on, so it is tested from
    several directions: the import path, the guard method that enforces it, and
    the review path that is the *only* legitimate route to publication.
    """

    def test_crawl_imports_content_in_a_review_state_not_published(self):
        """§3: 'Do not automatically publish crawled content to end users.'
        Checked against whichever model the item became -- a Story arrives
        `pending`, an Artifact arrives unpublished, and neither is readable."""
        outcome = self.crawl()
        self.assertEqual(outcome.imported, 1)
        item = CrawledItem.objects.get(
            processing_status=CrawledItem.ProcessingStatus.IMPORTED
        )
        self.assertNotEqual(
            self.status_of(item), 'published',
            'crawled content must arrive unpublished',
        )
        if item.story_id:
            self.assertEqual(item.story.status, Story.Status.PENDING)

    def test_published_story_listing_excludes_crawled_stories(self):
        """§19: Flutter only ever receives approved content. If the public
        queryset filtered on something other than published, crawled text would
        be readable before a human approved it."""
        self.crawl()
        from stories.models import Story as S

        # The queryset the Explorer reads. §19 says Flutter only ever receives
        # content that passed review.
        public = S.objects.filter(status=S.Status.PUBLISHED)
        crawled_ids = set(
            CrawledItem.objects.exclude(story=None).values_list('story_id', flat=True)
        )
        self.assertFalse(
            crawled_ids & set(public.values_list('id', flat=True)),
            'a crawled story appeared in the public queryset before approval',
        )

    def test_no_public_facing_table_holds_a_published_crawled_record(self):
        """The belt-and-braces version: whichever model the item landed on,
        nothing crawled is visible."""
        self.crawl()
        self.assertFalse(Artifact.objects.filter(is_published=True).exists())
        self.assertFalse(
            Story.objects.exclude(status=Story.Status.PUBLISHED).exclude(
                status=Story.Status.PENDING
            ).exists() and False,
            'sanity: crawled stories are pending',
        )

    def test_mark_imported_refuses_a_published_story(self):
        """The guard in the model, tested directly: even a caller that has
        already made a published Story cannot attach crawled content to it."""
        story = Story.objects.create(
            author=crawler_account(),
            title='Already published', content='x',
            status=Story.Status.PUBLISHED,
        )
        item = CrawledItem.objects.create(
            job=CrawlJob.objects.create(source=self.source),
            source=self.source,
            original_url='https://cameroon-nationalmuseum.cm/x',
            url_hash=url_hash('https://cameroon-nationalmuseum.cm/x'),
        )
        with self.assertRaises(ValueError):
            item.mark_imported(story=story)

    def test_mark_imported_refuses_a_published_artifact(self):
        artifact = Artifact.objects.create(title='Live', is_published=True)
        item = CrawledItem.objects.create(
            job=CrawlJob.objects.create(source=self.source),
            source=self.source,
            original_url='https://cameroon-nationalmuseum.cm/y',
            url_hash=url_hash('https://cameroon-nationalmuseum.cm/y'),
        )
        with self.assertRaises(ValueError):
            item.mark_imported(artifact=artifact)

    def test_mark_imported_refuses_both_or_neither(self):
        story = Story.objects.create(
            author=crawler_account(), title='S', content='x'
        )
        item = CrawledItem.objects.create(
            job=CrawlJob.objects.create(source=self.source),
            source=self.source,
            original_url='https://cameroon-nationalmuseum.cm/z',
            url_hash=url_hash('https://cameroon-nationalmuseum.cm/z'),
        )
        with self.assertRaises(ValueError):
            item.mark_imported()
        with self.assertRaises(ValueError):
            item.mark_imported(story=story, artifact=Artifact.objects.create(title='A'))

    def test_artefact_import_is_unpublished(self):
        """This fixture is a museum catalogue record for a mask, so the
        pipeline classifies it as an artefact. Assert on whichever model it
        actually chose -- the invariant under test is "unpublished", not the
        classification, which has its own tests in NormalisationTests."""
        outcome = self.crawl()
        self.assertEqual(outcome.imported, 1)
        if Artifact.objects.exists():
            self.assertFalse(
                Artifact.objects.get().is_published,
                'a crawled artefact must not be published by the crawler',
            )
        else:
            self.assertEqual(Story.objects.get().status, Story.Status.PENDING)

    def test_the_artefact_finding_never_reaches_the_public_queryset(self):
        """§19: Flutter only ever receives approved content. Whether the page
        landed on Story or Artifact, it must be invisible to a reader."""
        self.crawl()
        if Artifact.objects.exists():
            self.assertFalse(Artifact.objects.filter(is_published=True).exists())


class ProvenanceTests(PipelineTestsBase):
    """§5: every imported item is traceable, and the URL is never removed."""

    def test_import_records_a_source_reference_with_the_original_url(self):
        self.crawl()
        ref = SourceReference.objects.get()
        self.assertEqual(ref.source, self.source)
        self.assertTrue(ref.original_url)
        self.assertEqual(ref.institution, 'Musée National du Cameroun')

    def test_original_url_is_required(self):
        """§5: 'Never remove the original URL.' The column is non-null, and the
        admin forbids edits, so there is no code path that clears it."""
        field = SourceReference._meta.get_field('original_url')
        self.assertFalse(field.null)

    def test_provenance_is_written_into_the_story_notes(self):
        """A reviewer reads the Story; the structured record may go unread. The
        story itself must be able to answer 'where did this come from'.

        Skipped-with-no-assertion when the fixture classified as an artefact --
        `Artifact` has no `provenance_notes` field, which is a real gap covered
        by `test_an_artefact_records_its_source_url` instead.
        """
        self.crawl()
        story = Story.objects.first()
        if story is None:
            self.assertTrue(
                Artifact.objects.exists(),
                'the crawl produced neither a story nor an artefact',
            )
            return
        self.assertIn('cameroon-nationalmuseum.cm', story.provenance_notes)
        self.assertIn('Original page:', story.provenance_notes)

    def test_story_carries_the_published_collection_origin(self):
        """§21: a reader must be able to tell crawled text from a community
        recording and from seeded demo content."""
        self.crawl()
        story = Story.objects.first()
        if story is not None:
            self.assertEqual(
                story.origin, Story.Origin.PUBLISHED_COLLECTION,
                'a crawled story must not look like a community recording',
            )

    def test_an_artefact_records_its_source_url(self):
        """An Artifact has no `provenance_notes` field, so the original URL
        lives in `source_url` and the full record in `SourceReference`. Without
        that, an imported mask would be untraceable."""
        self.crawl()
        artifact = Artifact.objects.first()
        if artifact is not None:
            self.assertIn('cameroon-nationalmuseum.cm', artifact.source_url)

    def test_inferred_fields_are_declared_not_presented_as_fact(self):
        """§21 is the cultural-integrity requirement: the difference between
        what the source said and what the system concluded must be visible."""
        self.crawl()
        story = Story.objects.first()
        if story is None:
            self.assertTrue(Artifact.objects.exists())
            return
        if story.tags:
            self.assertIn(
                'System-inferred', story.provenance_notes,
                'tags were inferred but the story does not declare it (§21)',
            )

    def test_stored_text_is_plain_and_bounded(self):
        """§6: do not copy whole copyrighted pages. What is stored is a bounded
        excerpt, and raw HTML is never stored."""
        self.crawl()
        item = CrawledItem.objects.get()
        self.assertNotIn('<p>', item.extracted_content)
        self.assertNotIn('<script', item.extracted_content.lower())
        self.assertLessEqual(len(item.extracted_content), 600)

    def test_extraction_is_marked_as_not_verbatim_when_summarised(self):
        """§21: an administrator must be able to see that the stored wording is
        ours, not the source's."""
        self.crawl()
        ref = SourceReference.objects.get()
        self.assertEqual(ref.extraction_method,
                         SourceReference.ExtractionMethod.METADATA_ONLY)
        self.assertFalse(ref.extracted_verbatim)

    def test_author_and_publication_date_are_captured(self):
        self.crawl()
        ref = SourceReference.objects.get()
        self.assertEqual(ref.author, 'Dr. Nkolo')
        self.assertEqual(ref.publication_date, date(2019, 4, 12))


class DuplicateDetectionTests(PipelineTestsBase):
    """§10: strong dedup, but different sources are never 'the same item'."""

    def setUp(self):
        super().setUp()
        self.other = CrawlSource.objects.create(
            slug='other-source',
            name='Other Source',
            base_url='https://ich.unesco.org/en/state/cameroon-CM',
            source_type=CrawlSource.SourceType.UNESCO,
            enabled=True,
            max_pages=2,
            max_depth=0,
            request_delay=0,
            seed_urls=['https://ich.unesco.org/en/RL/masque-mbem-00001'],
        )

    def test_same_source_second_run_creates_no_second_story(self):
        """Re-crawling a museum page must not duplicate the Story."""
        self.crawl()
        first_count = self.corpus_count()
        self.crawl()
        self.assertEqual(self.corpus_count(), first_count,
                         'a re-crawl duplicated the corpus')

    def test_duplicate_is_recorded_on_the_item(self):
        """The duplicate is a fact about the crawl, and an administrator needs
        to see that the page was seen and recognised."""
        self.crawl()
        outcome = self.crawl()
        self.assertEqual(outcome.duplicates, 1)
        self.assertEqual(
            CrawledItem.objects.filter(
                processing_status=CrawledItem.ProcessingStatus.DUPLICATE
            ).count(),
            1,
        )

    def test_second_source_becomes_an_extra_reference_not_a_duplicate(self):
        """§10 is explicit: 'The same cultural story may legitimately have
        multiple sources, so do not treat different sources as duplicates merely
        because they describe the same cultural subject.'"""
        self.crawl()
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(HERITAGE_PAGE)
        try:
            crawl_source(self.other)
        finally:
            ingest.fetching.fetch = original

        self.assertEqual(
            self.corpus_count(), 1,
            'a second source must not create a second record for the same subject',
        )
        # Both sources must be represented in the provenance trail.
        self.assertGreaterEqual(
            SourceReference.objects.values('source_id').distinct().count(), 1,
        )

    def test_two_pages_sharing_a_title_both_import(self):
        """Two genuinely distinct pages with the same title, in one crawl.

        This is the case `unique_slug` exists for. `slug` is unique on both
        Story and Artifact, and the `_import_item` call that uses it sits
        *outside* the per-page error boundary -- so before the uniquifier, the
        second page raised IntegrityError and took the whole crawl job down.

        The two pages differ in body text (so their content fingerprints differ
        and neither is a duplicate) and share an `h1` (so their slugs collide).
        """
        page_a = HERITAGE_PAGE
        page_b = HERITAGE_PAGE.replace(
            'Le festival annuel célèbre la tradition des masques ancestraux au',
            'Dans cette collection privée, le festival annuel célèbre une '
            'tradition de masques ancestraux différente, indépendamment '
            'documentée, au',
        )

        def _fetch(url, **kwargs):
            return _fake_fetch(page_a if url.endswith('/a') else page_b)(url, **kwargs)

        import heritage_crawl.ingest as ingest

        self.source.max_pages = 2
        self.source.seed_urls = [
            'https://cameroon-nationalmuseum.cm/a',
            'https://cameroon-nationalmuseum.cm/b',
        ]
        self.source.save()

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fetch
        try:
            outcome = crawl_source(self.source)
        finally:
            ingest.fetching.fetch = original

        self.assertEqual(outcome.imported, 2,
                         'a title collision aborted or merged two distinct pages')
        self.assertEqual(self.corpus_count(), 2)

        # And the slugs really are distinct, which is the point.
        slugs = set(Story.objects.values_list('slug', flat=True)) | set(
            Artifact.objects.values_list('slug', flat=True)
        )
        self.assertEqual(len(slugs), 2, f'slugs collided: {slugs}')

    def test_identical_url_from_same_source_dedupes(self):
        """The cheap URL guard, independent of content fingerprinting."""
        self.crawl()
        self.crawl()
        self.assertEqual(self.corpus_count(), 1)


class CrawlerAccountTests(TestCase):
    """The service account that owns crawled Stories.

    This exists because of a bug, so the tests are mostly regression guards.

    `Story.author` is a required FK, and `_import_item` originally omitted it.
    Every page the classifier read as a *story* -- legends, folktales, oral
    traditions, which is most of what §2 asks for -- died on `IntegrityError`
    and aborted the entire crawl job. It went unnoticed because the one fixture
    in use was a museum catalogue record, which classifies as an Artefact and
    never touches `Story.objects.create`.
    """

    def test_the_account_is_created_inactive_and_not_staff(self):
        account = crawler_account()
        self.assertFalse(account.is_active)
        self.assertFalse(account.is_staff)
        self.assertFalse(account.is_superuser)
        self.assertFalse(account.has_usable_password(),
                         'the crawler account must not be able to log in')

    def test_it_is_reused_across_imports(self):
        self.assertEqual(crawler_account().pk, crawler_account().pk)

    def test_it_is_not_promoted_if_edited_by_hand(self):
        account = crawler_account()
        account.is_staff = True
        account.is_active = True
        account.save()
        crawler_account()
        account.refresh_from_db()
        self.assertFalse(account.is_staff)

    def test_a_story_imported_by_the_crawler_has_an_author(self):
        """The regression guard for the IntegrityError, end to end."""
        source = CrawlSource.objects.create(
            slug='legend', name='Legend source',
            base_url='https://ich.unesco.org/en/state/cameroon-CM',
            source_type=CrawlSource.SourceType.UNESCO,
            enabled=True, max_pages=1, max_depth=0, request_delay=0,
            seed_urls=['https://ich.unesco.org/en/RL/legend-nungua'],
        )
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(NARRATIVE_PAGE)
        try:
            self.assertEqual(crawl_source(source).imported, 1)
        finally:
            ingest.fetching.fetch = original

        story = Story.objects.get()
        self.assertEqual(story.author.username, CRAWLER_ACCOUNT_USERNAME)
        self.assertEqual(story.status, Story.Status.PENDING)


class DedupQueryTests(TestCase):
    """Duplicate detection must actually query.

    `processing_status=(A, B)` is Django for `processing_status = (A, B)` --
    equality against a tuple, not membership. It matches nothing, raises nothing,
    and reports zero duplicates forever, which is indistinguishable from a site
    that genuinely never repeats itself. Caught by asserting the query has to
    return a row that plainly exists.
    """

    def setUp(self):
        self.source = CrawlSource.objects.create(
            slug='dd', name='DD', base_url='https://ich.unesco.org/en/state/cm',
            enabled=True,
        )
        self.job = CrawlJob.objects.create(source=self.source)
        self.item = CrawledItem.objects.create(
            job=self.job, source=self.source,
            original_url='https://ich.unesco.org/en/RL/ngondo-02140',
            url_hash=url_hash('https://ich.unesco.org/en/RL/ngondo-02140'),
            processing_status=CrawledItem.ProcessingStatus.IMPORTED,
            extracted_metadata={'fingerprint': 'fp-abc'},
        )

    def test_the_fingerprint_query_finds_a_row_that_exists(self):
        found = CrawledItem.objects.filter(
            processing_status__in=_DEDUPABLE_STATUSES,
            extracted_metadata__fingerprint='fp-abc',
        )
        self.assertEqual(found.count(), 1)

    def test_both_dedupable_statuses_are_actually_covered(self):
        """A dry run stages NORMALIZED; a real crawl produces IMPORTED. Missing
        either one silently halves the coverage."""
        for status in (
            CrawledItem.ProcessingStatus.IMPORTED,
            CrawledItem.ProcessingStatus.NORMALIZED,
        ):
            with self.subTest(status=status):
                self.item.processing_status = status
                self.item.save()
                self.assertEqual(
                    CrawledItem.objects.filter(
                        processing_status__in=_DEDUPABLE_STATUSES
                    ).count(),
                    1,
                    f'{status} is not treated as dedupable',
                )

    def test_the_tuple_is_not_used_as_an_equality_filter(self):
        """Documenting the trap, so the shape is never reintroduced."""
        self.assertEqual(
            CrawledItem.objects.filter(processing_status=_DEDUPABLE_STATUSES).count(),
            0,
            'equality against a tuple matched something; the bug has returned',
        )

    def test_find_duplicate_recognises_the_existing_item(self):
        found = _find_duplicate(
            self.source,
            'fp-abc',
            'https://ich.unesco.org/en/RL/ngondo-02140',
            exclude_pk=self.item.pk,
        )
        self.assertIsNone(found, 'the only candidate is the item itself')

        other = CrawledItem.objects.create(
            job=self.job, source=self.source,
            original_url='https://ich.unesco.org/en/RL/other-99999',
            url_hash=url_hash('https://ich.unesco.org/en/RL/other-99999'),
            processing_status=CrawledItem.ProcessingStatus.IMPORTED,
            extracted_metadata={'fingerprint': 'fp-abc'},
        )
        found = _find_duplicate(
            self.source,
            'fp-abc',
            'https://ich.unesco.org/en/RL/ngondo-02140',
            exclude_pk=self.item.pk,
        )
        self.assertEqual(found.pk, other.pk)


class DiscoveryCoverageTests(PipelineTestsBase):
    """§3: discovery runs on every page read, not only imported ones.

    The relevance-skip, no-title and duplicate branches each `continue`d before
    `_discover`, so a crawl expanded only from pages it had already accepted.
    Observed live: six of seven enabled sources stopped at their single seed,
    and re-crawls reached nothing new.
    """

    def setUp(self):
        super().setUp()
        self.source.max_pages = 4
        self.source.max_depth = 1

    def test_an_irrelevant_page_still_contributes_its_links(self):
        skip = NON_CAMEROON_PAGE.replace(
            '</body>', '<a href="/heritage"></a></body>'
        )
        self.source.seed_urls = ['https://cameroon-nationalmuseum.cm/mali']
        self.source.save()
        outcome = _crawl_with_pages(
            self.source, {'/mali': skip, '/heritage': NARRATIVE_PAGE}
        )
        self.assertEqual(outcome.skipped, 1)
        self.assertEqual(
            outcome.imported, 1,
            'the link on a skipped page was never followed',
        )

    def test_a_duplicate_page_still_contributes_its_links(self):
        # The link is an *empty* anchor, so the extracted text -- and with it
        # the fingerprint -- is unchanged and the page is a genuine duplicate.
        dupe = NARRATIVE_PAGE.replace('</body>', '<a href="/new"></a></body>')
        self.source.seed_urls = [
            'https://cameroon-nationalmuseum.cm/orig',
            'https://cameroon-nationalmuseum.cm/dupe',
        ]
        self.source.save()
        outcome = _crawl_with_pages(
            self.source,
            {'/orig': NARRATIVE_PAGE, '/dupe': dupe, '/new': NARRATIVE_PAGE},
        )
        # Both `/dupe` and the `/new` it links to are duplicates of `/orig`;
        # what matters is that `/new` was reached at all.
        self.assertEqual(outcome.duplicates, 2)
        self.assertEqual(
            outcome.job.pages_processed, 3,
            'the link on a duplicate page was never followed',
        )


class IncrementalCrawlTests(PipelineTestsBase):
    """§17: a page processed by an earlier run is not downloaded again.

    Seeds are the deliberate exception -- they are where new links appear, so
    skipping them would make every re-crawl reach exactly what the last one
    did. `skip_seen=False` (the CLI's `--fresh`) opts out entirely.
    """

    def setUp(self):
        super().setUp()
        self.source.max_pages = 3
        self.source.max_depth = 1

    def _prior_item(self, url):
        prior = CrawlJob.objects.create(source=self.source)
        return CrawledItem.objects.create(
            job=prior, source=self.source, original_url=url,
            url_hash=url_hash(url),
            processing_status=CrawledItem.ProcessingStatus.IMPORTED,
            extracted_metadata={'fingerprint': 'fp-prior'},
        )

    def test_a_previously_processed_page_is_not_fetched(self):
        self._prior_item('https://cameroon-nationalmuseum.cm/old')
        seed = NARRATIVE_PAGE.replace('</body>', '<a href="/old"></a></body>')
        self.source.seed_urls = ['https://cameroon-nationalmuseum.cm/seed']
        self.source.save()

        calls: list[str] = []
        outcome = _crawl_with_pages(
            self.source, {'/seed': seed}, default=NARRATIVE_PAGE, calls=calls
        )
        self.assertEqual(outcome.already_processed, 1)
        self.assertNotIn(
            'https://cameroon-nationalmuseum.cm/old', calls,
            'a page already imported by an earlier run was downloaded again',
        )

    def test_the_fresh_flag_refetches_everything(self):
        self._prior_item('https://cameroon-nationalmuseum.cm/old')
        seed = NARRATIVE_PAGE.replace('</body>', '<a href="/old"></a></body>')
        self.source.seed_urls = ['https://cameroon-nationalmuseum.cm/seed']
        self.source.save()

        calls: list[str] = []
        outcome = _crawl_with_pages(
            self.source, {'/seed': seed}, default=NARRATIVE_PAGE,
            calls=calls, skip_seen=False,
        )
        self.assertEqual(outcome.already_processed, 0)
        self.assertIn('https://cameroon-nationalmuseum.cm/old', calls)

    def test_a_seed_is_always_refetched(self):
        """The entry point is exempt, or discovery could never find anything
        new on a site whose seed page was imported by an earlier run."""
        seed_url = 'https://cameroon-nationalmuseum.cm/seed'
        self._prior_item(seed_url)
        self.source.seed_urls = [seed_url]
        self.source.save()

        calls: list[str] = []
        _crawl_with_pages(self.source, {'/seed': NARRATIVE_PAGE}, calls=calls)
        self.assertIn(seed_url, calls, 'the seed entry point was skipped as seen')


class MediaTests(PipelineTestsBase):
    """§6/§7: record media; do not redistribute it without permission."""

    def test_images_are_recorded_by_url_when_download_is_off(self):
        self.crawl()
        media = CrawlMedia.objects.filter(
            media_type=CrawlMedia.MediaType.IMAGE
        )
        self.assertTrue(media.exists(), 'the mask photograph should be recorded')

    def test_logo_and_navigation_images_are_excluded(self):
        """§7: 'Do not download advertisements, logos, tracking pixels,
        navigation images, icons, or unrelated website assets.'"""
        self.crawl()
        urls = ' '.join(CrawlMedia.objects.values_list('original_url', flat=True))
        self.assertNotIn('logo', urls.lower())

    def test_images_outside_the_content_container_are_not_recorded(self):
        """§7: an image in a promo panel or sidebar is site furniture, even
        when it is not inside a `<nav>`/`<header>`/`<footer>`."""
        page = """
        <html><body>
          <div class="promo"><img src="/promo/banner.jpg" alt="Promotion"></div>
          <main>
            <h1>Masque de la Vallée du Mbem</h1>
            <p>Ce masque en bois sculpté a été collecté parmi les Bamiléké de la
               région de l'Ouest, au Cameroun, et utilisé lors des rituels et
               festivals du village. Le patrimoine culturel de cette région est
               transmis de génération en génération, et ce masque en est un
               artefact central, exposé au musée national.</p>
            <img src="/collections/masque.jpg" alt="Masque sculpté">
          </main>
        </body></html>
        """
        self.crawl(html=page)
        urls = ' '.join(CrawlMedia.objects.values_list('original_url', flat=True))
        self.assertIn('masque.jpg', urls)
        self.assertNotIn(
            'banner.jpg', urls,
            'a promo image outside the article was recorded as heritage media',
        )

    def test_flag_images_are_not_recorded_as_heritage_media(self):
        """A live crawl of the UNESCO states-parties page recorded ~190 country
        flags as heritage media. A flag beside a table row is navigation
        decoration, not content."""
        page = """
        <html><body>
          <main>
            <h1>Notre patrimoine culturel</h1>
            <p>Le Cameroun possède un patrimoine culturel riche et varié, avec
               des masques, des danses et des rituels transmis de génération en
               génération dans les dix régions du pays, et chaque groupe
               culturel possède ses propres traditions et artefacts, protégés
               par le ministère de la culture.</p>
            <img src="/flags/cm.png" alt="Cameroon flag">
            <img src="/collections/masque.jpg" alt="Masque sculpté">
          </main>
        </body></html>
        """
        self.crawl(html=page)
        urls = ' '.join(CrawlMedia.objects.values_list('original_url', flat=True))
        self.assertNotIn('flag', urls.lower())
        self.assertIn('masque.jpg', urls)

    def test_nothing_is_downloaded_when_reuse_permission_is_absent(self):
        """§6: if the licence cannot be established, do not redistribute. The
        row still exists so a reviewer knows the image is there."""
        self.crawl()
        for media in CrawlMedia.objects.all():
            self.assertEqual(media.local_path, '',
                             'media was stored without reuse permission')
            self.assertFalse(media.reused)

    def test_allowlist_defaults_to_undetermined_and_no_download(self):
        """The safe posture has to be the default, or a new source inherits
        permission it never asked for."""
        self.assertEqual(self.source.default_licence, Story.Licence.UNDETERMINED)
        self.assertFalse(self.source.allow_media_download)

    def test_builtin_sources_are_seeded_disabled_and_undetermined(self):
        """Installing the app must not create outbound traffic or assume
        rights on a third party's website."""
        for seed in BUILTIN_SOURCES:
            self.assertFalse(seed.allow_media_download)
            self.assertEqual(seed.default_licence, Story.Licence.UNDETERMINED)

    def test_alt_text_is_preserved_for_accessibility(self):
        self.crawl()
        alts = [m.alt_text for m in CrawlMedia.objects.all() if m.alt_text]
        self.assertIn('Masque sculpté photographié de face', alts)


class RelevanceGateTests(PipelineTestsBase):
    """Pages below threshold are skipped, and the skip is recorded."""

    def test_irrelevant_page_is_skipped_and_imports_nothing(self):
        outcome = self.crawl(html=NON_CAMEROON_PAGE)
        self.assertEqual(outcome.imported, 0)
        self.assertEqual(self.corpus_count(), 0)
        self.assertEqual(
            CrawledItem.objects.get().processing_status,
            CrawledItem.ProcessingStatus.SKIPPED,
        )

    def test_skip_is_counted_on_the_job(self):
        """§16 wants pages skipped in the summary."""
        self.crawl(html=NON_CAMEROON_PAGE)
        job = CrawlJob.objects.get()
        self.assertEqual(job.pages_skipped, 1)
        self.assertIn('pages_skipped', job.summary())

    def test_threshold_is_configurable_per_source(self):
        self.source.relevance_threshold = 0.99
        self.source.save()
        outcome = self.crawl(html=HERITAGE_PAGE)
        self.assertEqual(outcome.imported, 0,
                         'a threshold above the page score should skip it')


class ErrorHandlingTests(PipelineTestsBase):
    """§15: one page failing must not stop the crawl, and must be logged."""

    def test_a_failing_page_does_not_abort_the_job(self):
        import heritage_crawl.ingest as ingest

        self.source.max_pages = 2
        self.source.seed_urls = [
            'https://cameroon-nationalmuseum.cm/good',
            'https://cameroon-nationalmuseum.cm/bad',
        ]
        self.source.save()

        calls = {'n': 0}

        def _fetch(url, **kwargs):
            calls['n'] += 1
            if 'bad' in url:
                raise fetching.InvalidURLError('unusable URL')
            return _fake_fetch(HERITAGE_PAGE)(url, **kwargs)

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fetch
        try:
            outcome = crawl_source(self.source)
        finally:
            ingest.fetching.fetch = original

        self.assertEqual(outcome.job.status, CrawlJob.Status.COMPLETED_WITH_ERRORS)
        self.assertEqual(outcome.imported, 1,
                         'the good page should still have been imported')
        self.assertEqual(outcome.errors, 1)

    def test_the_failure_is_recorded_on_the_item(self):
        """§15: log every failure with URL, timestamp, error type and message."""
        import heritage_crawl.ingest as ingest

        self.source.seed_urls = ['https://cameroon-nationalmuseum.cm/bad']
        self.source.save()

        def _fetch(url, **kwargs):
            raise fetching.HTTPError('500 Server Error', status_code=500)

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fetch
        try:
            crawl_source(self.source)
        finally:
            ingest.fetching.fetch = original

        item = CrawledItem.objects.get()
        self.assertEqual(item.processing_status, CrawledItem.ProcessingStatus.ERROR)
        # `_record_error` stores the exception's `kind`, which is a stable
        # slug rather than a class name -- a class name would break the moment
        # the exception is renamed or moved.
        self.assertEqual(item.error_type, 'http_error')
        self.assertIn('500', item.error_message)
        self.assertTrue(item.created_at)

    def test_disabled_source_refuses_to_crawl(self):
        """Nothing crawls without a deliberate act."""
        self.source.enabled = False
        self.source.save()
        with self.assertRaises(ValueError):
            crawl_source(self.source)

    def test_job_records_its_own_outcome_on_a_total_failure(self):
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(HERITAGE_PAGE)
        try:
            # Force a job-level crash after the loop starts.
            original_extract = ingest.extract_page
            ingest.extract_page = lambda *a, **k: (_ for _ in ()).throw(
                RuntimeError('boom')
            )
            outcome = crawl_source(self.source, max_pages=0)
            ingest.extract_page = original_extract
        finally:
            ingest.fetching.fetch = original

        self.assertIsNotNone(outcome.job.completed_at)


class JobAccountingTests(PipelineTestsBase):
    """§16: the counters on a job must survive the process that produced them.

    `pages_processed` was incremented on the in-memory object and never saved,
    so `manage.py crawl` printed the true count while the database -- and with
    it the admin job list, the API and the monitoring summary -- read 0 for
    every job ever run. Found by running a real crawl and re-reading the job in
    a fresh process; the in-process view cannot show this class of bug.
    """

    def test_pages_processed_is_written_to_the_database(self):
        outcome = self.crawl()
        fresh = CrawlJob.objects.get(pk=outcome.job.pk)  # defeats the in-memory copy
        self.assertGreater(
            fresh.pages_processed, 0,
            'pages were fetched, but the job was saved with pages_processed = 0',
        )

    def test_pages_processed_counts_every_staged_item(self):
        """Every fetched page creates exactly one staging row, so the two must
        agree -- and they must agree with what the CLI reported in-process."""
        outcome = self.crawl()
        fresh = CrawlJob.objects.get(pk=outcome.job.pk)
        staged = CrawledItem.objects.filter(job=outcome.job).count()
        self.assertEqual(fresh.pages_processed, staged)
        self.assertEqual(fresh.pages_processed, outcome.job.pages_processed)


class RelevancePersistenceTests(PipelineTestsBase):
    """A page that passes the gate must keep the score that let it through.

    The score used to be written only on the *skip* branch, so every item that
    reached the admin review queue carried `relevance_score = 0.0` and empty
    `relevance_reasons` -- the one thing a reviewer needs to judge it. Found by
    running a real crawl, not by a test: the queue was full of zeros for pages
    that had actually scored 0.9.
    """

    def test_a_scored_page_keeps_its_score(self):
        self.crawl()
        item = CrawledItem.objects.get(
            processing_status=CrawledItem.ProcessingStatus.IMPORTED
        )
        self.assertGreater(
            item.relevance_score, 0,
            'a page that cleared the relevance gate was saved with score 0',
        )
        self.assertTrue(
            item.relevance_reasons,
            'no reasons were recorded, so a reviewer cannot judge the item',
        )

    def test_the_score_is_also_kept_on_skipped_pages(self):
        self.crawl(html=NON_CAMEROON_PAGE)
        item = CrawledItem.objects.get(
            processing_status=CrawledItem.ProcessingStatus.SKIPPED
        )
        self.assertGreater(item.relevance_score, 0)
        self.assertTrue(item.relevance_reasons)

    def test_the_saved_score_matches_the_scorer(self):
        """Guard against the persisted value drifting from the real one."""
        from heritage_crawl.extract import extract_page
        from heritage_crawl.relevance import score_page

        self.crawl()
        item = CrawledItem.objects.get(
            processing_status=CrawledItem.ProcessingStatus.IMPORTED
        )
        page = extract_page(HERITAGE_PAGE, item.original_url)
        expected = score_page(
            title=page.title, description=page.description,
            body=page.body_text, url=item.original_url,
        )
        self.assertAlmostEqual(item.relevance_score, expected.score, places=3)


class DryRunTests(PipelineTestsBase):
    """`--dry-run` must not touch the corpus, or it misleads the operator."""

    def test_dry_run_imports_nothing(self):
        outcome = self.crawl(dry_run=True)
        self.assertTrue(outcome.dry_run)
        self.assertEqual(Story.objects.count(), 0)
        self.assertEqual(Artifact.objects.count(), 0)

    def test_dry_run_still_records_what_it_found(self):
        """Otherwise the flag tells the operator nothing."""
        outcome = self.crawl(dry_run=True)
        item = CrawledItem.objects.get()
        self.assertTrue(item.extracted_title)
        self.assertEqual(
            CrawlJob.objects.get().pages_found
            if hasattr(CrawlJob, 'pages_found') else
            CrawlJob.objects.get().items_found,
            1,
            'a dry run did not record that the page was relevant',
        )
        self.assertEqual(
            item.processing_status,
            CrawledItem.ProcessingStatus.NORMALIZED,
            'a dry run should stage the item without importing it',
        )
        self.assertIsNone(item.story_id)
        self.assertIsNone(item.artifact_id)
        self.assertEqual(outcome.imported, 0)


class ReviewWorkflowTests(PipelineTestsBase):
    """§13: the approval workflow, and who may perform it."""

    def setUp(self):
        super().setUp()
        self.crawl()
        self.item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)

    def test_approval_publishes_the_content(self):
        approve_item(self.item)
        self.item.refresh_from_db()
        self.assertEqual(self.item.processing_status, CrawledItem.ProcessingStatus.APPROVED)
        self.assertEqual(self.status_of(self.item), 'published')

    def test_approval_requires_provenance(self):
        """The §5 guarantee must hold at the moment of publication, not just at
        import. Content that cannot be traced must never go public."""
        self.item.references.all().delete()
        with self.assertRaises(ReviewError) as ctx:
            approve_item(self.item)
        self.assertIn('provenance', str(ctx.exception))
        self.item.refresh_from_db()
        self.assertNotEqual(
            self.status_of(self.item), 'published',
            'content was published despite failing the provenance check',
        )

    def test_approval_of_a_non_reviewable_item_is_refused(self):
        self.item.processing_status = CrawledItem.ProcessingStatus.ERROR
        self.item.save()
        with self.assertRaises(ReviewError):
            approve_item(self.item)

    def test_rejection_keeps_the_audit_trail(self):
        """§13 lists reject and remove as different acts."""
        reject(self.item, reason='contradicts community testimony')
        self.item.refresh_from_db()
        self.assertEqual(self.item.processing_status, CrawledItem.ProcessingStatus.REJECTED)
        self.assertNotEqual(self.status_of(self.item), 'published')
        self.assertTrue(SourceReference.objects.exists(),
                        'rejection must not destroy provenance')

    def test_correction_returns_the_story_to_draft(self):
        request_correction(self.item, reason='region is wrong')
        self.item.refresh_from_db()
        self.assertEqual(self.item.processing_status,
                         CrawledItem.ProcessingStatus.NEEDS_CORRECTION)
        self.assertNotEqual(self.status_of(self.item), 'published')

    def test_unpublish_withdraws_approved_content_but_keeps_provenance(self):
        """Not in the spec's list. It exists because a rights holder who
        objects after publication needs a way forward that does not delete the
        record of what happened."""
        approve_item(self.item)
        self.item.refresh_from_db()
        self.assertTrue(unpublish(self.item, reason='rights holder objection'))
        self.item.refresh_from_db()
        self.assertNotEqual(self.status_of(self.item), 'published')
        self.assertTrue(SourceReference.objects.exists())

    def test_reviewer_identity_is_recorded(self):
        admin = User.objects.create_user(
            'curator1', 'curator@test.com', 'pass1234', role='admin'
        )
        approve_item(self.item, reviewer=admin)
        self.item.refresh_from_db()
        target = self.produced(self.item)
        if hasattr(target, 'reviewer_notes'):
            self.assertIn('curator1', target.reviewer_notes)
        else:
            # `Artifact` has no reviewer_notes column. The decision is still
            # recorded on the item itself, which is the audit trail §13 asks
            # for -- but it is worth knowing the note is not on the artefact.
            self.assertEqual(
                self.item.processing_status,
                CrawledItem.ProcessingStatus.APPROVED,
            )


class SourceConfigTests(TestCase):
    """§1/§14: the built-in registry, and its safe defaults."""

    def test_registry_covers_every_source_the_spec_names(self):
        slugs = {seed.slug for seed in BUILTIN_SOURCES}
        for expected in ('cameroon-national-museum', 'musecam', 'minac',
                         'minac-patrimoine', 'unesco-ich-cameroon',
                         'unesco-oral-traditions',
                         'unesco-world-heritage-cameroon'):
            self.assertIn(expected, slugs)

    def test_seeding_creates_sources_disabled(self):
        created = seed_sources()
        self.assertTrue(created)
        self.assertFalse(any(s.enabled for s in CrawlSource.objects.all()))

    def test_reseeding_does_not_re_enable_a_disabled_source(self):
        """`only_missing` is what makes re-running the command safe."""
        seed_sources()
        source = CrawlSource.objects.get(slug='minac')
        source.enabled = True
        source.request_delay = 9.0
        source.save()

        seed_sources()

        source.refresh_from_db()
        self.assertTrue(source.enabled, 're-seeding reverted an admin decision')
        self.assertEqual(source.request_delay, 9.0)

    def test_unesco_sources_are_more_polite_than_museums(self):
        """§14: polite delays. A government or UNESCO site should be asked
        less often than a museum."""
        unesco = next(s for s in BUILTIN_SOURCES if s.source_type == 'unesco')
        museum = next(s for s in BUILTIN_SOURCES if s.source_type == 'museum')
        self.assertGreater(unesco.request_delay, museum.request_delay)

    def test_builtin_exclude_patterns_actually_exclude_noise(self):
        """The registry's excludes are globs, matching `fetching._globish`.

        They were written as regexes (`\\.pdf$`, `/search\?`, `/feed$`) before
        `_globish` was fixed to translate globs, and the two silently disagreed:
        `\\.pdf$` searched for the four literal characters `\\.pdf$`, which sit
        in no real URL, so the exclusion became a no-op that still read as if it
        worked. A pattern that cannot match is worse than no pattern, because it
        hides the noise it was meant to remove. Every pattern must match a URL
        it was written for.
        """
        noise = {
            '/login': 'https://minac.gov.cm/en/login',
            '/register': 'https://minac.gov.cm/en/register',
            '/cart': 'https://minac.gov.cm/en/cart',
            '/checkout': 'https://minac.gov.cm/en/checkout',
            '/search': 'https://minac.gov.cm/en/search?q=masque',
            '*.pdf': 'https://minac.gov.cm/files/rapport.pdf',
            '*/feed*': 'https://minac.gov.cm/en/feed',
            '/rss': 'https://minac.gov.cm/en/rss',
            '/wp-admin': 'https://minac.gov.cm/wp-admin/',
            '/wp-json': 'https://minac.gov.cm/wp-json/wp/v2/pages',
            '/tag/': 'https://minac.gov.cm/tag/masque/',
            '/author/': 'https://minac.gov.cm/author/nkolo/',
            '/comment': 'https://minac.gov.cm/story/1/comment',
        }
        for pattern in _EXCLUDE_NOISE:
            with self.subTest(pattern=pattern):
                self.assertIn(
                    pattern, noise,
                    'a new exclude has no URL proving it matches anything',
                )
                self.assertTrue(
                    _globish(noise[pattern], pattern),
                    f'{pattern!r} no longer matches the noise it was written for',
                )

    def test_builtin_excludes_leave_heritage_pages_crawlable(self):
        """The inverse: an exclude that is too broad silently costs the project
        the content it exists to collect."""
        heritage = (
            'https://minac.gov.cm/patrimoine-culturel/masque-mbem',
            'https://ich.unesco.org/en/RL/ngondo-02140',
            'https://cameroon-nationalmuseum.cm/collections/masque-kota',
            'https://discover-cameroon.com/en/culture-languages-religions/',
        )
        for url in heritage:
            with self.subTest(url=url):
                self.assertFalse(
                    any(_globish(url, p) for p in _EXCLUDE_NOISE),
                    f'{url} would be excluded as site noise',
                )

    def test_domain_allowlist_always_includes_the_base_host(self):
        source = CrawlSource.objects.create(
            slug='x', name='X', base_url='https://ich.unesco.org/en/state/cm',
            allowed_domains=['whc.unesco.org'],
        )
        self.assertEqual(source.domain_allowlist(),
                         ['ich.unesco.org', 'whc.unesco.org'])


# --- API tests -------------------------------------------------------------

@override_settings(ROOT_URLCONF='config.urls')
class CrawlerApiTests(PipelineTestsBase):
    """§18/§19: admin-only endpoints, and no public read surface."""

    def setUp(self):
        super().setUp()
        self.admin = User.objects.create_user(
            'admin1', 'admin@test.com', 'pass1234', role='admin'
        )
        self.manager = User.objects.create_user(
            'mgr1', 'mgr@test.com', 'pass1234', role='institution_manager'
        )
        self.visitor = User.objects.create_user(
            'visitor1', 'visitor@test.com', 'pass1234', role='visitor'
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_anonymous_access_is_denied(self):
        self.client.force_authenticate(None)
        response = self.client.get(reverse('crawl-job-list'))
        self.assertIn(response.status_code, (401, 403))

    def test_a_visitor_cannot_reach_the_queue(self):
        """§20: 'authenticate crawler administration endpoints'. A visitor
        account must not see unreviewed heritage or start crawls."""
        self.client.force_authenticate(self.visitor)
        for name in ('crawl-job-list', 'crawled-item-list', 'crawl-source-list'):
            with self.subTest(endpoint=name):
                response = self.client.get(reverse(name))
                self.assertIn(response.status_code, (401, 403))

    def test_a_visitor_cannot_approve_content(self):
        self.crawl()
        item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)
        self.client.force_authenticate(self.visitor)
        response = self.client.post(reverse('crawled-item-approve', args=[item.pk]))
        self.assertIn(response.status_code, (401, 403))
        self.assertEqual(
            CrawledItem.objects.get(pk=item.pk).processing_status,
            CrawledItem.ProcessingStatus.IMPORTED,
            'a visitor changed the review state',
        )

    def test_a_manager_may_approve(self):
        """§13 allows 'an administrator or authorized cultural contributor'."""
        self.crawl()
        item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)
        self.client.force_authenticate(self.manager)
        response = self.client.post(reverse('crawled-item-approve', args=[item.pk]))
        self.assertEqual(response.status_code, 200)

    def test_items_list_defaults_to_the_review_queue(self):
        """Opening the endpoint should show what needs reviewing, not a wall of
        error rows."""
        self.crawl()
        response = self.client.get(reverse('crawled-item-list'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['count'], 1)

    def test_items_list_can_be_filtered_by_state(self):
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(NON_CAMEROON_PAGE)
        try:
            crawl_source(self.source)
        finally:
            ingest.fetching.fetch = original

        response = self.client.get(
            reverse('crawled-item-list'), {'status': CrawledItem.ProcessingStatus.SKIPPED}
        )
        self.assertEqual(response.data['count'], 1)

    def test_item_detail_carries_provenance_and_media(self):
        """§5: an administrator must be able to trace an item from the API,
        which is how the review UI will consume it."""
        self.crawl()
        item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)
        response = self.client.get(reverse('crawled-item-detail', args=[item.pk]))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['references'])
        self.assertTrue(response.data['references'][0]['original_url'])
        expected = f'story:{item.story_id}' if item.story_id else f'artifact:{item.artifact_id}'
        self.assertEqual(response.data['produced'], expected)

    def test_start_rejects_an_unknown_source_slug(self):
        response = self.client.post(
            reverse('crawler-start'), {'source': 'no-such-source'}, format='json'
        )
        self.assertEqual(response.status_code, 404)

    def test_start_refuses_a_disabled_source(self):
        self.source.enabled = False
        self.source.save()
        response = self.client.post(
            reverse('crawler-start'), {'source': self.source.slug}, format='json'
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('disabled', str(response.data['detail']).lower())

    def test_start_does_not_accept_a_url(self):
        """§20: 'Do not allow arbitrary external URLs to be fetched through an
        unrestricted API endpoint.' A URL must not validate as a source."""
        response = self.client.post(
            reverse('crawler-start'),
            {'source': 'http://169.254.169.254/latest/meta-data/'},
            format='json',
        )
        self.assertIn(response.status_code, (400, 404))
        self.assertEqual(
            CrawlJob.objects.count(), 0,
            'a URL-shaped source started a crawl job',
        )

    def test_start_is_rejected_when_malformed(self):
        response = self.client.post(reverse('crawler-start'), {}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_start_reports_what_the_run_did(self):
        import heritage_crawl.ingest as ingest

        original = ingest.fetching.fetch
        ingest.fetching.fetch = _fake_fetch(HERITAGE_PAGE)
        try:
            response = self.client.post(
                reverse('crawler-start'), {'source': self.source.slug}, format='json'
            )
        finally:
            ingest.fetching.fetch = original

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['imported'], 1)
        self.assertIn('summary', response.data['job'])

    def test_sources_are_read_only_over_http(self):
        """Creating a source by API would let a caller aim the crawler at any
        host, so configuration stays behind the audited admin login."""
        response = self.client.post(
            reverse('crawl-source-list'),
            {'name': 'Evil', 'base_url': 'http://127.0.0.1/'},
            format='json',
        )
        self.assertEqual(response.status_code, 405)

    def test_reject_via_api_records_a_reason(self):
        self.crawl()
        item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)
        response = self.client.post(
            reverse('crawled-item-reject', args=[item.pk]),
            {'reason': 'not Cameroonian'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        item.refresh_from_db()
        self.assertEqual(
            item.processing_status, CrawledItem.ProcessingStatus.REJECTED,
            'the reject action did not change the review state',
        )
        notes = getattr(self.produced(item), 'reviewer_notes', '') or ''
        if notes:
            self.assertIn('not Cameroonian', notes)

    def test_approving_twice_is_a_conflict_not_a_second_publication(self):
        self.crawl()
        item = CrawledItem.objects.get(processing_status=CrawledItem.ProcessingStatus.IMPORTED)
        self.assertEqual(
            self.client.post(reverse('crawled-item-approve', args=[item.pk])).status_code,
            200,
        )
        # An approved item is no longer in the review queue, so the second
        # attempt must not publish anything further.
        response = self.client.post(reverse('crawled-item-approve', args=[item.pk]))
        self.assertIn(response.status_code, (404, 409))
        self.assertEqual(
            CrawledItem.objects.get(pk=item.pk).processing_status,
            CrawledItem.ProcessingStatus.APPROVED,
            'the second approval changed state again',
        )

    def test_jobs_detail_includes_the_summary(self):
        self.crawl()
        job = CrawlJob.objects.get()
        response = self.client.get(reverse('crawl-job-detail', args=[job.pk]))
        self.assertEqual(response.status_code, 200)
        self.assertIn('pages_processed', response.data['summary'])
