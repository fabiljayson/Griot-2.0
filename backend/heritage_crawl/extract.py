"""Turning a fetched page into structured, plain-text fields.

The central decision in this module is that **raw HTML is never stored**. Every
value that leaves `extract_page` is plain text: tags are stripped, entities are
decoded once, and whitespace is collapsed. That is a stronger control than
sanitising markup and then storing it (§20 lists "sanitize extracted HTML" and
"prevent malicious content injection" as separate requirements, and it is worth
noting that sanitising HTML correctly is a decade-old problem while not storing
HTML at all is not a problem at all).

The corollary, which §6 and §21 care about: what we keep is the source's own
wording. Nothing is paraphrased, completed or inferred here. Field-mapping and
inference live in `normalize.py` and are recorded as such.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from urllib.parse import urljoin

from bs4 import BeautifulSoup

log = logging.getLogger('heritage_crawl.extract')

#: Dropped wholesale. `nav`/`footer` removal alone is not enough — heritage
#: sites put tag clouds and "related stories" inside `<div>`s — so a small set
#: of role-based and class-name-based exclusions runs too.
_DROP_TAGS = (
    'script', 'style', 'noscript', 'iframe', 'svg', 'form',
    'nav', 'header', 'footer', 'aside', 'button', 'select',
)

_DROP_CLASS_HINTS = (
    'cookie', 'consent', 'newsletter', 'subscribe', 'social', 'share',
    'breadcrumb', 'sidebar', 'widget', 'comment', 'advert', 'ads-', 'promo',
    'related', 'footer', 'header', 'nav', 'menu', 'skip', 'toolbar',
)

#: Boilerplate that survives structural stripping on some sites.
_TEXT_NOISE = (
    re.compile(r'^\s*(accept|manage)?\s*(all\s+)?cookies?\b.*$', re.I | re.M),
    re.compile(r'^\s*javascript\s+(is\s+)?(required|disabled)\b.*$', re.I | re.M),
    re.compile(r'^\s*(sign in|log ?in|register|subscribe)\s*\|?\s*$', re.I | re.M),
    re.compile(r'^\s*share (this|on)\b.*$', re.I | re.M),
    re.compile(r'^\s*©\s*\d{4}.*$', re.M),
    re.compile(r'^\s*all rights reserved\.?\s*$', re.I | re.M),
)

_WS_RUN = re.compile(r'[ \t ]+')
_BLANK_RUN = re.compile(r'\n{3,}')


@dataclass
class ExtractedPage:
    """Everything we managed to read off one page.

    Every field is optional and defaults to empty, because §4 is explicit:
    "If a field cannot be reliably extracted, store NULL or an equivalent empty
    value." Inventing a plausible value here would be the single worst thing
    this module could do to a heritage corpus.
    """

    url: str
    title: str = ''
    alt_title: str = ''
    description: str = ''
    body_text: str = ''
    author: str = ''
    institution: str = ''
    publication_date: str = ''
    language: str = ''
    headings: list[str] = field(default_factory=list)
    images: list[dict] = field(default_factory=list)
    documents: list[dict] = field(default_factory=list)
    links: list[str] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)

    @property
    def text_for_scoring(self) -> str:
        return f'{self.title} {self.alt_title} {self.description} {self.body_text}'


def _clean_text(value: str | None) -> str:
    """Collapse a text run to a single normalised form."""
    if not value:
        return ''
    value = BeautifulSoup(value, 'lxml').get_text(' ', strip=True)
    value = _WS_RUN.sub(' ', value)
    return value.strip()


def _strip_noise(text: str) -> str:
    for pattern in _TEXT_NOISE:
        text = pattern.sub('', text)
    return _BLANK_RUN.sub('\n\n', text).strip()


def _strip_boilerplate(soup: BeautifulSoup) -> None:
    """Remove chrome in place, by tag then by class/id hints.

    Both passes materialise their list *before* decomposing anything. Beautiful
    Soup's `find_all` walks the live tree, and `decompose()` detaches the node
    and its whole subtree -- so decomposing during iteration leaves the walk
    holding a reference to something already gone. On real pages this surfaced
    as `AttributeError: 'NoneType' object has no attribute 'get'` from inside
    bs4 itself, which aborted every item from the four live sources that have a
    deeply nested wrapper div. It never appeared in tests because every fixture
    is a flat document with no nesting to invalidate.
    """
    for tag in list(soup.find_all(_DROP_TAGS)):
        tag.decompose()

    # Attributes are read for every tag before any of them is removed, for the
    # same reason: a decompose in the middle of this pass would invalidate the
    # remaining tags.
    doomed = []
    for tag in list(soup.find_all(True)):
        attrs = ' '.join(filter(None, [
            ' '.join(tag.get('class', []) or []),
            tag.get('id') or '',
            tag.get('role') or '',
        ])).lower()
        if attrs and any(hint in attrs for hint in _DROP_CLASS_HINTS):
            doomed.append(tag)

    for tag in doomed:
        # A tag may already be detached because an ancestor was decomposed in
        # an earlier iteration; `decompose()` on a detached node is a no-op in
        # current bs4 but not in all versions, and `extract()` is safe either
        # way.
        try:
            tag.decompose()
        except (AttributeError, ValueError):
            tag.extract()


def _main_content(soup: BeautifulSoup):
    """The densest plausible content container.

    Heritage pages are inconsistent, so this tries the usual semantic
    containers first and only falls back to `<body>`.
    """
    for selector in ('article', 'main', '[role="main"]', '#content', '.content',
                     '.entry-content', '.post-content'):
        found = soup.select_one(selector)
        if found and len(found.get_text(strip=True)) > 200:
            return found
    return soup.body or soup


def _extract_title(soup: BeautifulSoup) -> tuple[str, str]:
    """Return (title, alternative title).

    The alternative title is the `<title>` when it differs from the `<h1>`,
    because on heritage sites they frequently differ meaningfully — the `<h1>`
    is the artefact's name and the `<title>` carries the museum and region.
    Both are kept rather than one being discarded (§4 lists "alternative title").
    """
    h1 = soup.find('h1')
    heading = _clean_text(h1.get_text()) if h1 else ''

    raw = soup.find('title')
    doc_title = _clean_text(raw.get_text()) if raw else ''

    if heading and doc_title:
        for suffix in (' | ', ' - ', ' – ', ' :: ', ' — '):
            if doc_title.endswith(suffix + heading):
                doc_title = doc_title[: -len(suffix + heading)].strip()
                break
    if heading and doc_title.lower() == heading.lower():
        doc_title = ''

    title = heading or doc_title
    alt = doc_title if doc_title and doc_title != title else ''
    return title, alt


def _extract_meta(soup: BeautifulSoup, base_url: str) -> dict:
    """Read the metadata that source pages actually publish."""

    def meta(*names: str) -> str:
        for name in names:
            for attr in ('name', 'property', 'itemprop'):
                tag = soup.find('meta', attrs={attr: name})
                if tag and tag.get('content'):
                    return _clean_text(tag['content'])
        return ''

    published = meta(
        'article:published_time', 'datePublished', 'dc.date',
        'dc.date.issued', 'date', 'publish-date', 'og:published_time',
    )

    return {
        'author': meta('author', 'article:author', 'dc.creator', 'byl'),
        'institution': meta(
            'og:site_name', 'dc.publisher', 'publisher', 'citation_publisher',
        ),
        'publication_date': published,
        'language': meta('og:locale', 'content-language', 'language', 'dc.language'),
        'description': meta('description', 'og:description', 'dc.description'),
        'licence': meta('dcterms.license', 'license', 'dc.license', 'rights'),
        'canonical_url': _meta_content(soup, 'og:url', 'canonical') or '',
    }


def _meta_content(soup: BeautifulSoup, *names: str) -> str:
    for name in names:
        tag = soup.find('meta', attrs={'property': name}) or soup.find(
            'meta', attrs={'name': name}
        )
        if tag and tag.get('content'):
            return tag['content'].strip()
    if 'canonical' in names:
        link = soup.find('link', rel='canonical')
        if link and link.get('href'):
            return link['href'].strip()
    return ''


def _extract_images(soup: BeautifulSoup, base_url: str) -> list[dict]:
    """Content images only.

    §7: "Do not download advertisements, logos, tracking pixels, navigation
    images, icons". The filters below are heuristics, and they are the right
    shape of heuristic — a crawler that quietly archives a site's logo onto a
    heritage record is worse than one that misses an image.
    """
    out: list[dict] = []
    for tag in soup.find_all('img'):
        src = (
            tag.get('src')
            or tag.get('data-src')
            or tag.get('data-original')
            or ''
        ).strip()
        if not src or src.startswith('data:'):
            continue

        identity = ' '.join(filter(None, [
            src, tag.get('alt', ''), tag.get('class', ' ')[0] if tag.get('class') else '',
        ])).lower()
        if any(
            hint in identity
            for hint in ('logo', 'icon', 'sprite', 'avatar', 'banner-ad',
                         'pixel', 'spacer', 'blank', 'placeholder',
                         'loading', 'badge', 'gravatar', 'favicon')
        ):
            continue
        if src.endswith('.svg'):
            # Listed in §7 as a type we may encounter, but a site logo drawn in
            # SVG is almost always the site's own mark rather than content.
            continue

        width = _int_attr(tag, 'width')
        height = _int_attr(tag, 'height')
        if width and height and (width < 120 or height < 120):
            continue

        out.append({
            'url': urljoin(base_url, src),
            'alt': _clean_text(tag.get('alt', '')),
            'title': _clean_text(tag.get('title', '')),
            'declared_width': width,
            'declared_height': height,
        })
    return out


def _int_attr(tag, name: str) -> int | None:
    raw = (tag.get(name) or '').strip().rstrip('px')
    try:
        return int(raw) if raw else None
    except ValueError:
        return None


def _extract_documents(soup: BeautifulSoup, base_url: str) -> list[dict]:
    """Linked PDFs and other documents (§7 lists PDF as a type)."""
    out: list[dict] = []
    for tag in soup.find_all('a', href=True):
        href = tag['href'].strip()
        if not href.lower().split('?')[0].endswith('.pdf'):
            continue
        out.append({
            'url': urljoin(base_url, href),
            'label': _clean_text(tag.get_text()),
        })
    return out


def _extract_links(soup: BeautifulSoup, base_url: str) -> list[str]:
    out: list[str] = []
    for tag in soup.find_all('a', href=True):
        href = tag['href'].strip()
        if href.startswith(('mailto:', 'tel:', 'javascript:', 'data:')):
            continue
        try:
            out.append(urljoin(base_url, href))
        except ValueError:
            continue
    return out


def _extract_date(value: str) -> str:
    """Normalise whatever date format the page used to an ISO date.

    Returns '' rather than guessing when the input is not a date. A wrong date
    in a provenance record is worse than a missing one, because §5 asks an
    administrator to trust that field.
    """
    if not value:
        return ''
    value = value.strip()

    iso = re.match(r'^(\d{4})-(\d{2})-(\d{2})', value)
    if iso:
        return iso.group(0)

    for pattern in (r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})',):
        found = re.search(pattern, value)
        if found:
            day, month, year = found.groups()
            return f'{year}-{int(month):02d}-{int(day):02d}'

    found = re.search(
        r'(January|February|March|April|May|June|July|August|September|'
        r'October|November|December)\s+(\d{1,2}),?\s+(\d{4})',
        value,
        re.I,
    )
    if found:
        months = {
            m.lower(): i
            for i, m in enumerate(
                ['January', 'February', 'March', 'April', 'May', 'June',
                 'July', 'August', 'September', 'October', 'November', 'December'],
                1,
            )
        }
        month_name, day, year = found.groups()
        return f'{year}-{months[month_name.lower()]:02d}-{int(day):02d}'

    found = re.search(
        r'(\d{1,2})\s+(January|February|March|April|May|June|July|August|'
        r'September|October|November|December)\s+(\d{4})',
        value,
        re.I,
    )
    if found:
        months = {
            m.lower(): i
            for i, m in enumerate(
                ['January', 'February', 'March', 'April', 'May', 'June',
                 'July', 'August', 'September', 'October', 'November', 'December'],
                1,
            )
        }
        day, month_name, year = found.groups()
        return f'{year}-{months[month_name.lower()]:02d}-{int(day):02d}'

    return ''


def extract_page(html: str, url: str) -> ExtractedPage:
    """Parse one page into plain-text fields.

    Malformed markup is expected, not exceptional: heritage sites are frequently
    hand-edited and inconsistently nested. BeautifulSoup's `lxml` parser recovers
    rather than raising, and anything genuinely unparseable raises
    `BeautifulSoup`'s own exception for the caller to record as an item error.
    """
    soup = BeautifulSoup(html, 'lxml')

    # Strip chrome *before* reading anything. Doing it afterwards leaves the
    # nav, footer and cookie banner in `body_text`, which is exactly the noise
    # the whole module exists to keep out of the corpus.
    _strip_boilerplate(soup)

    title, alt_title = _extract_title(soup)
    meta = _extract_meta(soup, url)

    container = _main_content(soup)
    body = _strip_noise(_clean_text(container.get_text('\n')))

    headings = [
        _clean_text(h.get_text())
        for h in container.find_all(['h1', 'h2', 'h3'])
        if _clean_text(h.get_text())
    ]

    page = ExtractedPage(
        url=url,
        title=title,
        alt_title=alt_title,
        description=meta.get('description', ''),
        body_text=body,
        author=meta.get('author', ''),
        institution=meta.get('institution', ''),
        publication_date=_extract_date(meta.get('publication_date', '')),
        language=(meta.get('language') or '')[:8],
        headings=headings[:40],
        images=_extract_images(soup, url),
        documents=_extract_documents(soup, url),
        links=_extract_links(soup, url),
        metadata=meta,
    )

    # If the page had no meta description, the lead paragraph is a better answer
    # than an empty string — but it is still the source's wording, not a summary.
    if not page.description and body:
        page.description = _lead_sentences(body)

    return page


def _lead_sentences(text: str, max_length: int = 400) -> str:
    """First one or two complete sentences, source wording untouched."""
    flat = _WS_RUN.sub(' ', text).strip()
    parts = re.split(r'(?<=[.!?])\s+', flat)
    out: list[str] = []
    for sentence in parts:
        if len(' '.join([*out, sentence])) > max_length:
            break
        out.append(sentence)
        if len(out) == 2:
            break
    return ' '.join(out).strip()


def summarise(text: str, max_length: int = 600) -> str:
    """A bounded excerpt for storage, clearly *not* a paraphrase.

    §6 permits storing "a short factual summary" instead of full text. This
    takes the opening of the source's own text and truncates at a sentence
    boundary. It is deterministic, it is the source's wording, and it is marked
    `extracted_verbatim=False` on the `SourceReference` that records it so a
    reviewer knows they are not looking at an untouched quotation.
    """
    if len(text) <= max_length:
        return text
    cut = text[:max_length]
    for boundary in ('. ', '.\n', '! ', '? '):
        position = cut.rfind(boundary)
        if position > max_length * 0.5:
            return cut[: position + 1].strip()
    return cut.rsplit(' ', 1)[0].rstrip(' ,;:-') + '…'