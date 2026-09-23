"""HTTP session and page fetching for the Cameroon crawler."""

import logging
import time

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


def fetch_page(url: str) -> BeautifulSoup | None:
    """Fetch a page with retries and polite delay."""
    full_url = url if url.startswith("http") else config.BASE_URL + url
    for attempt in range(1, config.MAX_RETRIES + 1):
        try:
            log.info(f"Fetching {full_url} (attempt {attempt})")
            resp = _session.get(full_url, timeout=config.REQUEST_TIMEOUT)
            resp.raise_for_status()
            time.sleep(config.REQUEST_DELAY)
            return BeautifulSoup(resp.text, "lxml")
        except requests.RequestException as e:
            log.warning(f"  Attempt {attempt} failed: {e}")
            if attempt < config.MAX_RETRIES:
                time.sleep(2 ** attempt)
    log.error(f"  Failed to fetch {full_url} after {config.MAX_RETRIES} attempts")
    return None


def download_stream(url: str, timeout: int = config.REQUEST_TIMEOUT) -> requests.Response:
    """Stream an image download response using the shared session."""
    return _session.get(url, timeout=timeout, stream=True)