"""HTTP session and page fetching for the Cameroon crawler.

Every outbound request — page fetches, image downloads, and each redirect hop —
passes through `guard_url`. Crawled pages are third-party input: a hostile or
compromised page can link `http://169.254.169.254/latest/meta-data/` (cloud
metadata), `http://127.0.0.1:8000/admin/` (the very backend this crawler feeds),
or `http://10.0.0.5/` on the operator's LAN, and the response would be stored
and reviewed as if it were heritage content. SSRF, not a hypothetical: the
crawler runs in CI and on developer machines that sit on real networks.
"""

import ipaddress
import logging
import socket
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

import config

log = logging.getLogger("crawler")

_session = requests.Session()
_session.headers.update({
    "User-Agent": (
        "Mozilla/5.0 (compatible; CameroonContentCrawler/1.0; "
        "+https://discover-cameroon.com)"
    )
})

MAX_REDIRECTS = 5
_REDIRECT_STATUSES = {301, 302, 303, 307, 308}


class SsrfBlockedError(ValueError):
    """A URL pointed somewhere the crawler must never fetch."""


def guard_url(url: str) -> None:
    """Reject non-HTTP schemes and hosts that resolve to non-public IP space.

    Every resolved address must be globally routable: `is_global` covers
    loopback, RFC1918 private, link-local (169.254/16 — cloud metadata lives
    here), CGNAT, reserved, multicast and unspecified ranges for both IPv4 and
    IPv6 in one check, and IPv4-mapped IPv6 (`::ffff:127.0.0.1`) is unwrapped
    before testing so it cannot smuggle a loopback address past the guard.

    Known limit, accepted here: the check and the connection are two steps, so
    a DNS record that flips between them (rebinding) can still win. Closing
    that needs a transport that connects to the pre-resolved address; for a
    crawler that follows links off third-party pages the resolution check is
    the standard baseline, and redirect hops below are re-checked the same way.
    """
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise SsrfBlockedError(f"blocked scheme {parsed.scheme!r} in {url}")
    if not parsed.hostname:
        raise SsrfBlockedError(f"no host in {url}")

    try:
        infos = socket.getaddrinfo(
            parsed.hostname, parsed.port, proto=socket.IPPROTO_TCP
        )
    except (socket.gaierror, ValueError) as exc:
        # gaierror: does not resolve. ValueError: unusable port/hostname.
        raise SsrfBlockedError(f"cannot resolve {parsed.hostname!r} in {url}") from exc

    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        mapped = getattr(addr, "ipv4_mapped", None)
        if mapped is not None:
            addr = mapped
        if not addr.is_global:
            raise SsrfBlockedError(
                f"host {parsed.hostname!r} in {url} resolves to non-public {addr}"
            )


def _get(
    url: str,
    *,
    stream: bool = False,
    timeout: int = config.REQUEST_TIMEOUT,
) -> requests.Response:
    """GET [url] with every redirect hop re-validated.

    `requests` follows redirects on its own, which would happily walk a
    302 from an allowed host straight into metadata service. Each hop gets
    the same guard as the first request instead.
    """
    current = url
    for _ in range(MAX_REDIRECTS + 1):
        guard_url(current)
        resp = _session.get(
            current, timeout=timeout, stream=stream, allow_redirects=False
        )
        if (
            resp.status_code in _REDIRECT_STATUSES
            and resp.headers.get("location")
        ):
            location = urljoin(current, resp.headers["location"])
            resp.close()
            current = location
            continue
        return resp
    raise SsrfBlockedError(f"more than {MAX_REDIRECTS} redirects fetching {url}")


def fetch_page(url: str) -> BeautifulSoup | None:
    """Fetch a page with retries and polite delay."""
    full_url = url if url.startswith("http") else config.BASE_URL + url
    try:
        guard_url(full_url)
    except SsrfBlockedError as e:
        # Returning None matches every other failure mode here, and runner.py
        # already skips pages that come back empty.
        log.warning(f"Blocked URL {full_url}: {e}")
        return None
    for attempt in range(1, config.MAX_RETRIES + 1):
        try:
            log.info(f"Fetching {full_url} (attempt {attempt})")
            resp = _get(full_url)
            resp.raise_for_status()
            time.sleep(config.REQUEST_DELAY)
            return BeautifulSoup(resp.text, "lxml")
        except SsrfBlockedError as e:
            # A redirect to blocked space is a decision, not a transient
            # failure: retrying spends the whole backoff to reach the same
            # wall.
            log.warning(f"Blocked while fetching {full_url}: {e}")
            return None
        except requests.RequestException as e:
            log.warning(f"  Attempt {attempt} failed: {e}")
            if attempt < config.MAX_RETRIES:
                time.sleep(2 ** attempt)
    log.error(f"  Failed to fetch {full_url} after {config.MAX_RETRIES} attempts")
    return None


def download_stream(url: str, timeout: int = config.REQUEST_TIMEOUT) -> requests.Response:
    """Stream an image download response using the shared session."""
    # SsrfBlockedError propagates on purpose: images.py catches it as a
    # per-image failure, and a blocked URL must not be retried or written.
    return _get(url, timeout=timeout, stream=True)
