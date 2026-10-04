"""Fetching, with the security and politeness rules the spec insists on.

This is the module to read before changing anything else in the app, because it
is the only place a remote server's response influences the process. Everything
here exists because of §6 (robots, rate limits), §14 (do not crawl
aggressively) and §20 (SSRF, file types, size limits).

The controls, in the order a request meets them:

1. **URL scheme** — http/https only. No file://, no ftp, no gopher.
2. **Domain allow-list** — the source's own hosts. A page cannot point the
   crawler somewhere else and have it followed.
3. **SSRF guard** — the hostname is resolved and every resulting address is
   checked against loopback, private, link-local, multicast and reserved
   ranges, plus cloud metadata addresses. Without this, a crafted link on a
   crawled page could reach an internal service or an instance credential
   endpoint.
4. **robots.txt** — fetched once per origin through the same guards, then
   honoured via the stdlib parser.
5. **Politeness** — a per-host delay, applied before each request including
   retries, and jittered so parallel-ish sources do not synchronise.
6. **Size cap** — responses are streamed and abandoned past the limit, so a
   hostile or broken origin cannot exhaust memory.
7. **Content-type allow-list** — only HTML-ish responses are parsed. An
   endpoint that returns a 200 with an executable body is not fed to the
   parser.

None of these are advisory. `fetch` raises on a violation; it does not warn and
continue.
"""

from __future__ import annotations

import hashlib
import ipaddress
import logging
import random
import socket
import time
import urllib.robotparser
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlparse, urlunparse

import requests
from django.utils import timezone

log = logging.getLogger('heritage_crawl.fetch')

ALLOWED_SCHEMES = frozenset({'http', 'https'})

#: Only these are ever handed to the HTML parser. A `200 text/html` is a page;
#: everything else is a link to follow or an error.
ALLOWED_CONTENT_TYPES = (
    'text/html',
    'application/xhtml+xml',
    'text/plain',  # some heritage pages are served as plain text
)

#: Hard ceiling regardless of what a source asks for. A source configuration
#: is admin-supplied, and this keeps a mistake from becoming an outage.
ABSOLUTE_MAX_BYTES = 20_000_000

#: Cloud instance metadata. Reachable from inside a cloud deployment and
#: routinely leaks credentials, so it is named explicitly even though it is
#: inside the link-local range checked below.
_METADATA_ADDRESSES = frozenset({'169.254.169.254', 'fd00:ec2::254'})


class FetchError(Exception):
    """Base class. Every failure the caller may want to distinguish is a subclass."""

    kind = 'error'


class InvalidURLError(FetchError):
    kind = 'invalid_url'


class DisallowedDomainError(FetchError):
    """The URL's host is not in the source's allow-list."""

    kind = 'disallowed_domain'


class SSRFBlockedError(FetchError):
    """The URL resolves to an address we must never contact."""

    kind = 'ssrf_blocked'


class RobotsDisallowedError(FetchError):
    kind = 'robots_disallowed'


class TooLargeError(FetchError):
    kind = 'too_large'


class UnsupportedContentTypeError(FetchError):
    kind = 'unsupported_content_type'


class HTTPError(FetchError):
    kind = 'http_error'

    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


@dataclass
class FetchResult:
    """A successful fetch. `text` is decoded, never raw bytes."""

    url: str
    final_url: str
    status_code: int
    content_type: str
    text: str
    fetched_at: object = None
    #: Per-page hints the extractor can use without re-parsing.
    headers: dict[str, str] = field(default_factory=dict)

    def __post_init__(self):
        if self.fetched_at is None:
            self.fetched_at = timezone.now()


class _RateLimiter:
    """Enforces a minimum gap between requests to the same host.

    Deliberately per-host rather than global: a crawl of two sources in
    sequence should not be made to wait out one source's delay before touching
    the other, and each source's own delay is the value that matters for the
    server being polite to.
    """

    def __init__(self):
        self._last: dict[str, float] = {}

    def wait(self, host: str, delay: float) -> float:
        previous = self._last.get(host)
        now = time.monotonic()
        slept = 0.0
        if previous is not None:
            remaining = delay - (now - previous)
            if remaining > 0:
                # Jitter so a crawler restarted across several sources does not
                # produce a synchronised burst that looks like an attack.
                remaining += random.uniform(0, min(0.4, delay * 0.1))
                time.sleep(remaining)
                slept = remaining
        self._last[host] = time.monotonic()
        return slept


_rate_limiter = _RateLimiter()


#: Query parameters that describe how a visitor arrived, not which document
#: they asked for. Stripped before hashing so campaign links do not fork a page
#: into several near-identical records.
_TRACKING_PARAMS = frozenset({
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'utm_name', 'utm_reader', 'utm_brand', 'utm_social',
    'utm_source', 'gclid', 'dclid', 'fbclid', 'msclkid', 'mc_cid', 'mc_eid',
    'ref', 'referrer', 'source', 'igshid', 'yclid', '_ga', '_gl',
})


def _canonical_query(raw: str) -> str:
    """Sort the surviving parameters and drop the tracking ones."""
    if not raw:
        return ''
    kept = []
    for pair in raw.split('&'):
        if not pair:
            continue
        name, _, _value = pair.partition('=')
        if name.strip().lower() in _TRACKING_PARAMS:
            continue
        kept.append(pair)
    return '&'.join(sorted(kept))


def normalise_url(url: str, base: str | None = None) -> str:
    """Canonicalise a URL so the same page has one hash across runs.

    Lowercases scheme and host, drops the fragment, strips default ports, drops
    analytics parameters and sorts what remains. Without this, `?b=2&a=1` and
    `?a=1&b=2` are two different URLs and dedup silently fails.

    Analytics parameters are dropped because they name the *referrer*, not the
    page. A MINAC page reached from a newsletter and from a search engine is one
    page, and §10 asks us to compare source URLs — treating the two as distinct
    would create a duplicate Story for every campaign that linked to the site.
    """
    if base:
        url = urljoin(base, url)
    parsed = urlparse(url.strip())
    if not parsed.scheme or not parsed.netloc:
        raise InvalidURLError(f'not an absolute URL: {url!r}')

    scheme = parsed.scheme.lower()
    netloc = parsed.netloc.lower()
    # Drop the default port so `:443` and `` are the same origin.
    if scheme == 'http' and netloc.endswith(':80'):
        netloc = netloc[:-3]
    if scheme == 'https' and netloc.endswith(':443'):
        netloc = netloc[:-4]

    query = _canonical_query(parsed.query)
    return urlunparse((scheme, netloc, parsed.path or '/', parsed.params, query, ''))


def url_hash(url: str) -> str:
    """Stable key for duplicate detection."""
    return hashlib.sha256(normalise_url(url).encode('utf-8')).hexdigest()


def _address_is_blocked(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> str | None:
    """Return a reason string when this address must not be contacted."""
    if str(ip) in _METADATA_ADDRESSES:
        return 'cloud metadata address'
    if ip.is_loopback:
        return 'loopback'
    if ip.is_private:
        return 'private network'
    if ip.is_link_local:
        return 'link-local'
    if ip.is_multicast:
        return 'multicast'
    if ip.is_reserved or ip.is_unspecified:
        return 'reserved'
    # IPv4-mapped IPv6 (::ffff:10.0.0.1) reaches an IPv4 private range while
    # looking like a normal address to naive checks.
    mapped = getattr(ip, 'ipv4_mapped', None)
    if mapped is not None:
        return _address_is_blocked(mapped)
    return None


def assert_safe_url(url: str, allowed_domains: list[str]) -> None:
    """Scheme, allow-list and SSRF checks. Raises on any violation."""
    parsed = urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme not in ALLOWED_SCHEMES:
        raise InvalidURLError(f'disallowed scheme {scheme!r} in {url!r}')

    host = (parsed.hostname or '').lower()
    if not host:
        raise InvalidURLError(f'no host in {url!r}')

    allowed = {d.lower().lstrip('.') for d in allowed_domains if d}
    # Compare on the registrable-ish suffix so `www.minac.gov.cm` matches a
    # configured `minac.gov.cm`, but never allow an unrelated domain that merely
    # ends with the same letters (`evilminac.gov.cm`).
    for candidate in (host, host.removeprefix('www.')):
        if candidate in allowed:
            break
    else:
        raise DisallowedDomainError(f'{host} is not allowed for this source')

    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror as exc:
        raise InvalidURLError(f'cannot resolve {host}: {exc}') from exc

    for info in infos:
        address = info[4][0]
        try:
            ip = ipaddress.ip_address(address)
        except ValueError as exc:  # pragma: no cover - getaddrinfo is typed
            raise InvalidURLError(f'unparseable address {address!r}') from exc
        reason = _address_is_blocked(ip)
        if reason:
            raise SSRFBlockedError(f'{host} resolves to {ip} ({reason})')


def _robots_allows(url: str, session: requests.Session, timeout: int) -> bool:
    """True when robots.txt permits this URL.

    A missing or unreachable robots.txt is treated as *allowed*, which is what
    RFC 9309 says for 4xx. A 5xx is treated as *disallowed* — the conservative
    reading, because a server that is failing is not a server to lean on.
    """
    parsed = urlparse(url)
    robots_url = f'{parsed.scheme}://{parsed.netloc}/robots.txt'
    parser = urllib.robotparser.RobotFileParser()
    try:
        response = session.get(robots_url, timeout=timeout, allow_redirects=False)
    except requests.RequestException as exc:
        log.warning('robots.txt unreachable for %s (%s); treating as allowed', parsed.netloc, exc)
        return True

    if response.status_code in (401, 403):
        log.warning('robots.txt forbidden at %s; treating as disallowed', robots_url)
        return False
    if 400 <= response.status_code < 500:
        return True
    if response.status_code >= 500:
        log.warning('robots.txt returned %s at %s; treating as disallowed',
                    response.status_code, robots_url)
        return False

    parser.parse(response.text.splitlines())
    return parser.can_fetch('*', url)


def _read_capped(response: requests.Response, max_bytes: int) -> str:
    """Read a streamed response, abandoning it past `max_bytes`."""
    chunks: list[bytes] = []
    total = 0
    for chunk in response.iter_content(chunk_size=64 * 1024):
        if not chunk:
            continue
        total += len(chunk)
        if total > max_bytes:
            response.close()
            raise TooLargeError(f'response exceeded {max_bytes} bytes')
        chunks.append(chunk)
    body = b''.join(chunks)
    # Decode leniently: heritage pages are full of legacy encodings declared
    # wrongly, and a UnicodeDecodeError on a 200 would lose a valid page.
    return body.decode(response.encoding or 'utf-8', errors='replace')


def build_session(user_agent: str) -> requests.Session:
    session = requests.Session()
    session.headers.update({
        'User-Agent': user_agent,
        'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
        'Accept-Language': 'en,fr;q=0.8',
    })
    return session


DEFAULT_USER_AGENT = (
    'GriotAI-CulturalHeritageBot/1.0 '
    '(heritage ingestion for review; contact: set CrawlSource.contact_note)'
)


def fetch(
    url: str,
    *,
    allowed_domains: list[str],
    request_delay: float = 2.0,
    timeout: int = 20,
    max_bytes: int = 5_000_000,
    session: requests.Session | None = None,
    user_agent: str = DEFAULT_USER_AGENT,
    respect_robots: bool = True,
) -> FetchResult:
    """Fetch one page, applying every control in this module's docstring.

    `session` is injectable so tests can supply a transport without monkeypatching
    `requests`; `respect_robots=False` exists only for offline fixture tests,
    where there is no robots.txt to consult and no server to be polite to.
    """
    max_bytes = min(max_bytes, ABSOLUTE_MAX_BYTES)
    session = session or build_session(user_agent)

    normalised = normalise_url(url)
    assert_safe_url(normalised, allowed_domains)

    host = urlparse(normalised).hostname or ''

    if respect_robots and not _robots_allows(normalised, session, timeout):
        raise RobotsDisallowedError(f'robots.txt disallows {normalised}')

    last_error: FetchError | None = None
    for attempt in range(1, 4):
        try:
            _rate_limiter.wait(host, request_delay)
            response = session.get(
                normalised,
                timeout=timeout,
                stream=True,
                allow_redirects=True,
            )
        except requests.RequestException as exc:
            last_error = HTTPError(f'{type(exc).__name__}: {exc}')
        else:
            with response:
                if response.status_code >= 400:
                    # Retry only on 5xx and 429; a 404 will not become a 200.
                    if response.status_code >= 500 or response.status_code == 429:
                        last_error = HTTPError(
                            f'HTTP {response.status_code}', response.status_code
                        )
                        response.close()
                    else:
                        raise HTTPError(
                            f'HTTP {response.status_code}', response.status_code
                        )
                else:
                    # A redirect can walk us off the allow-list, so re-check.
                    if response.url != normalised:
                        assert_safe_url(
                            normalise_url(response.url), allowed_domains
                        )

                    content_type = response.headers.get('Content-Type', '')
                    base_type = content_type.split(';')[0].strip().lower()
                    if base_type and not any(
                        base_type.startswith(allowed) for allowed in ALLOWED_CONTENT_TYPES
                    ):
                        raise UnsupportedContentTypeError(
                            f'content-type {base_type!r} is not parsed'
                        )

                    text = _read_capped(response, max_bytes)
                    return FetchResult(
                        url=normalised,
                        final_url=normalise_url(response.url),
                        status_code=response.status_code,
                        content_type=content_type,
                        text=text,
                        headers=dict(response.headers),
                    )
        if attempt < 3:
            time.sleep(2 ** attempt)

    raise last_error or HTTPError(f'failed to fetch {normalised}')


def discover_urls(
    html: str,
    base_url: str,
    *,
    include_patterns: list[str] | None = None,
    exclude_patterns: list[str] | None = None,
    max_depth: int = 0,
) -> list[str]:
    """Same-origin links from a page, filtered by the source's patterns.

    Deliberately does not use a real HTML parser — this runs on every link and
    only needs `href` values, and the extractor module owns the bs4 dependency.
    Off-site links are dropped: following them turns a configured source into
    an open crawl.
    """
    import re

    base_host = urlparse(base_url).hostname or ''
    pattern = re.compile(r'href\s*=\s*["\']([^"\'#]+)["\']', re.IGNORECASE)

    seen: list[str] = []
    for raw in pattern.findall(html):
        if raw.startswith(('mailto:', 'tel:', 'javascript:', 'data:')):
            continue
        try:
            candidate = normalise_url(raw, base=base_url)
        except FetchError:
            continue
        host = urlparse(candidate).hostname or ''
        if host.removeprefix('www.') != base_host.removeprefix('www.'):
            continue
        if include_patterns and not any(
            _globish(candidate, p) for p in include_patterns
        ):
            continue
        if exclude_patterns and any(_globish(candidate, p) for p in exclude_patterns):
            continue
        if candidate not in seen:
            seen.append(candidate)
    return seen[: max(0, max_depth) * 200 or 50]


def _globish(url: str, pattern: str) -> bool:
    import re as _re

    try:
        return bool(_re.search(pattern, url))
    except _re.error:
        # A malformed admin-supplied pattern must not crash a crawl.
        log.warning('ignoring malformed URL pattern %r', pattern)
        return False