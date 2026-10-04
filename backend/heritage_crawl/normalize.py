"""Mapping an extracted page onto the models this project already has.

This is where the spec's §12 suggested model list meets §11's instruction to
reuse what exists. A crawled page becomes a `Story` when it reads as prose, and
an `Artifact` when it reads as a description of an object. Both already have
status, rights and provenance fields, and both are already wired to the admin
dashboard and the Flutter client — which is the whole reason this module
exists instead of a parallel `CulturalContent` table.

Two rules run through everything below:

**Nothing is invented.** §4 says "Do not invent missing information. If a field
cannot be reliably extracted, store NULL or an equivalent empty value." So a
page with no stated author gets `''`, not a guess at the museum's press office,
and a page with no stated cultural group gets no cultural group — even though
the URL contains a region name.

**System inference is labelled.** §21 requires that a reader and an
administrator be able to tell source-supported information from inferred
information. `NormalizedItem.inferred_fields` records exactly which values came
from our reasoning rather than the page, and that list is persisted on the
`CrawledItem` so it survives into review.
"""

from __future__ import annotations

import hashlib
import re
import unicodedata
from dataclasses import dataclass, field
from uuid import uuid4

from django.utils.text import slugify as django_slugify

from qr_codes.models import Artifact

from .extract import ExtractedPage, summarise
from .relevance import RelevanceResult

#: `relevance.classify_content_types` emits descriptive labels, but
#: `Artifact.ContentType` has its own small closed vocabulary. The two are not
#: the same taxonomy and no single mapping is correct, which is the reason
#: `ContentType` and `Category` are separate fields on the model — so the
#: translation is explicit and lives here rather than being guessed inline.
CONTENT_TYPE_MAP = {
    'artifact': Artifact.ContentType.ARTIFACT,
    'heritage_site': Artifact.ContentType.LANDMARK,
    'legend': Artifact.ContentType.LEGEND,
    'tradition': Artifact.ContentType.CULTURE,
    'music': Artifact.ContentType.CULTURE,
    'oral_history': Artifact.ContentType.CULTURE,
    'language': Artifact.ContentType.CULTURE,
    'cuisine': Artifact.ContentType.CULTURE,
}

#: Material vocabulary, used only for `Artifact.Category`. A page that reads as
#: an artefact but names no material gets `Category.OTHER`, which the model
#: documents as "we looked and it genuinely does not fit" — distinct from
#: `ContentType.UNKNOWN`, which means "nothing classified it".
_MATERIAL_TERMS = {
    Artifact.Category.SCULPTURE: (
        'sculpture', 'statue', 'statuette', 'carving', 'carved', 'figurine',
        'bas-relief', 'relief', 'effigy',
    ),
    Artifact.Category.MASK: ('mask', 'masquerade', 'helmet mask'),
    Artifact.Category.POTTERY: (
        'pottery', 'pot', 'vase', 'terracotta', 'ceramic', 'earthenware', 'jar',
    ),
    Artifact.Category.TEXTILE: (
        'textile', 'cloth', 'cotton', 'embroidery', 'embroidered', 'wrapper',
        'garment', 'attire',
    ),
    Artifact.Category.FABRIC: (
        'raffia', 'fibre', 'fiber', 'weaving', 'loom', 'woven', 'plaited',
        'basket',
    ),
    Artifact.Category.INSTRUMENT: (
        'drum', 'xylophone', 'balafon', 'horn', 'flute', 'rattle', 'musical',
        'instrument', 'kenkeni',
    ),
    Artifact.Category.JEWELRY: (
        'necklace', 'bracelet', 'bead', 'beads', 'earring', 'bangle', 'jewellery',
        'jewelry', 'anklet',
    ),
    Artifact.Category.WEAPON: (
        'spear', 'sword', 'dagger', 'shield', 'matchet', 'cutlass', 'machete',
    ),
    Artifact.Category.TOOL: ('hoe', 'fishing net', 'farm tool', 'agricultural'),
}


def normalise_title(value: str) -> str:
    """Fold a title to a comparison key.

    Unicode-folded, punctuation-stripped, lowercased. Used for duplicate
    detection only — the stored title is always the source's.
    """
    if not value:
        return ''
    folded = unicodedata.normalize('NFKD', value)
    folded = folded.encode('ascii', 'ignore').decode('ascii').lower()
    folded = re.sub(r'[^a-z0-9]+', ' ', folded)
    return ' '.join(folded.split())


def content_fingerprint(title: str, body: str) -> str:
    """A content hash for near-duplicate detection across sources.

    §10 warns that "the same cultural story may legitimately have multiple
    sources, so do not treat different sources as duplicates merely because they
    describe the same cultural subject." So this keys on the *text*, not the
    subject: two sources describing the Bamileke mask tradition will not match
    each other, but the same page reached via two URLs will.
    """
    basis = normalise_title(title) or normalise_title(body[:200])
    folded = unicodedata.normalize('NFKD', body[:2000]).encode(
        'ascii', 'ignore'
    ).decode('ascii').lower()
    folded = re.sub(r'[^a-z0-9]+', ' ', folded).strip()
    return hashlib.sha256(f'{basis}|{folded}'.encode('utf-8')).hexdigest()


def unique_slug(title: str, *, fallback: str = 'item', exists=None) -> str:
    """Django-compatible slug, non-empty, and not already taken.

    Heritage titles are full of characters `slugify` strips (accents are fine,
    but a title that is entirely non-Latin would collapse to ''), hence the
    fallback.

    The uniqueness loop is not polish. `Story.slug` and `Artifact.slug` are
    `unique=True`, and two distinct pages from the same museum routinely share a
    title ("Masque", "Masque (recto)", a category index and the item it lists).
    Without this the second import raises `IntegrityError` inside `_import_item`,
    and because that call sits outside the per-page error boundary a single
    colliding title would abort the whole crawl job.

    `exists` is a callable taking a slug and returning a bool; it is injected so
    this function stays free of model imports and testable on its own.
    """
    slug = django_slugify(title)[:200] or fallback
    if exists is None:
        return slug
    if not exists(slug):
        return slug
    for suffix in range(2, 1000):
        candidate = f'{slug[:200 - len(str(suffix)) - 1]}-{suffix}'
        if not exists(candidate):
            return candidate
    return f'{slug[:190]}-{uuid4().hex[:8]}'


@dataclass
class NormalizedItem:
    """A page mapped to the fields of a Story or an Artifact."""

    kind: str  # 'story' | 'artifact'
    title: str
    slug: str
    summary: str = ''
    content: str = ''
    #: `Artifact.Category` value — the object's material.
    category: str = ''
    #: `Artifact.ContentType` value — what kind of thing this is.
    content_type: str = ''
    #: The descriptive label `relevance` produced, kept for the metadata blob
    #: so a reviewer can see the pre-translation reasoning.
    descriptive_type: str = ''
    cultural_group: str = ''
    region: str = ''
    locality: str = ''
    language: str = ''
    historical_period: str = ''
    tags: list[str] = field(default_factory=list)
    museum_name: str = ''
    source_label: str = ''
    #: Which of the above the *system* decided rather than read off the page.
    inferred_fields: list[str] = field(default_factory=list)
    fingerprint: str = ''

    def as_metadata(self) -> dict:
        """The subset persisted on `CrawledItem.extracted_metadata`."""
        return {
            'kind': self.kind,
            'title': self.title,
            'slug': self.slug,
            'summary': self.summary,
            'category': self.category,
            'content_type': self.content_type,
            'descriptive_type': self.descriptive_type,
            'cultural_group': self.cultural_group,
            'region': self.region,
            'language': self.language,
            'tags': self.tags,
            'inferred_fields': self.inferred_fields,
            'fingerprint': self.fingerprint,
        }


def _pick_content_type(relevance: RelevanceResult) -> str:
    """Best descriptive label for this page, artefact-shaped winning."""
    for candidate in relevance.content_types:
        if candidate == 'artifact':
            return candidate
    return relevance.content_types[0] if relevance.content_types else ''


def _artifact_content_type(descriptive: str) -> str:
    """Translate a descriptive label into an `Artifact.ContentType` value.

    `UNKNOWN` rather than a guess: the model documents that value as "the row
    exists but nothing has classified it yet", which is exactly the truth when a
    page gives us nothing to go on.
    """
    return CONTENT_TYPE_MAP.get(descriptive, Artifact.ContentType.UNKNOWN)


def _artifact_category(text: str) -> str:
    """Best `Artifact.Category` for the object's material, or `other`."""
    lowered = text.lower()
    best, best_hits = Artifact.Category.OTHER, 0
    for category, terms in _MATERIAL_TERMS.items():
        hits = sum(1 for term in terms if term in lowered)
        if hits > best_hits:
            best, best_hits = category, hits
    return best


def normalize_page(
    page: ExtractedPage,
    relevance: RelevanceResult,
    *,
    store_full_text: bool = False,
    max_content_chars: int = 4000,
) -> NormalizedItem:
    """Map an extracted page to a Story or an Artifact shape.

    `store_full_text` is False by default because §6 asks us not to store whole
    copyrighted pages. What gets stored is a title, a description, a bounded
    excerpt of the source's own wording, and the structured fields — which is
    exactly the fallback the spec describes. Sources whose terms permit more can
    set it per-source.
    """
    inferred: list[str] = []

    title = (page.title or page.alt_title or '').strip()
    if not title:
        # A page with no usable heading is not a heritage record; the caller
        # records it as skipped rather than inventing a title from a URL slug.
        title = ''

    content_type = _pick_content_type(relevance)
    kind = 'artifact' if content_type == 'artifact' else 'story'
    if kind == 'artifact':
        inferred.append('kind:artefact')
        artifact_category = _artifact_category(page.body_text)
        artifact_content_type = _artifact_content_type(content_type)
        if artifact_category != Artifact.Category.OTHER:
            inferred.append(f'category:{artifact_category}')
    else:
        artifact_category = ''
        artifact_content_type = ''

    if store_full_text:
        content = page.body_text[:max_content_chars]
    else:
        content = summarise(page.body_text, max_length=max_content_chars)

    region = relevance.region
    if region:
        inferred.append('region:detected-in-text')

    cultural_group = relevance.cultural_groups[0] if relevance.cultural_groups else ''
    if cultural_group:
        # Supported by the source naming it, per §9. Not location-derived.
        pass

    museum = page.institution or ''
    if museum:
        inferred.append('museum:institution-metadata')

    tags = sorted({
        *relevance.content_types,
        *relevance.cultural_groups,
        *relevance.languages,
        *([relevance.region] if relevance.region else []),
    })

    return NormalizedItem(
        kind=kind,
        title=title,
        slug=unique_slug(title or page.url),
        summary=summarise(page.description or page.body_text, max_length=400),
        content=content,
        category=artifact_category,
        content_type=artifact_content_type,
        descriptive_type=content_type,
        cultural_group=cultural_group,
        region=region,
        language=relevance.languages[0] if relevance.languages else '',
        historical_period='',
        tags=tags,
        museum_name=museum,
        inferred_fields=sorted(set(inferred)),
        fingerprint=content_fingerprint(title, page.body_text),
    )