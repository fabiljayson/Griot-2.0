"""The ingestion pipeline.

`crawl_source` is the whole flow in one place, in the order §3 specifies:

    URL discovery -> robots/policy -> download -> extraction -> relevance
    -> normalisation -> dedup -> metadata -> provenance -> DB -> review

It is written as one linear function with a per-item error boundary rather than
a framework, because a crawl is a batch job that a person runs and then reads
the log of. §15 is explicit that "a failure on one page must not stop the
entire crawl", so every per-page step is wrapped and recorded on the
`CrawledItem` instead of propagating.

The pipeline deliberately stops at review. Nothing here sets a Story to
published or an Artifact's `is_published`; both enter as pending, which is §3
("Do not automatically publish crawled content") and §13 (the workflow starts at
CRAWLED and a human moves it).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from django.db import transaction
from django.utils import timezone

from . import fetching
from .extract import extract_page
from .fetching import FetchError
from .models import CrawledItem, CrawlJob, CrawlMedia, CrawlSource, SourceReference
from .normalize import normalize_page, unique_slug
from .relevance import is_relevant, score_page

log = logging.getLogger('heritage_crawl.ingest')


@dataclass
class CrawlOutcome:
    """What one run did. Returned so callers can report and assert."""

    job: CrawlJob
    imported: int = 0
    duplicates: int = 0
    skipped: int = 0
    errors: int = 0
    media_recorded: int = 0
    already_processed: int = 0
    item_ids: list[int] = field(default_factory=list)
    dry_run: bool = False


def _seed_urls(source: CrawlSource) -> list[str]:
    """Start points for this source.

    Stored as a JSON list on the source rather than in code, so adding a page
    to a museum's site is an admin edit. Falls back to the base URL.
    """
    urls = list(source.seed_urls or [])
    return urls or [source.base_url]


def _record_error(item: CrawledItem, exc: Exception) -> None:
    kind = getattr(exc, 'kind', None) or type(exc).__name__
    item.processing_status = CrawledItem.ProcessingStatus.ERROR
    item.error_type = kind
    item.error_message = str(exc)[:2000]
    item.save(
        update_fields=['processing_status', 'error_type', 'error_message', 'updated_at']
    )
    log.warning('item failed (%s): %s', kind, exc)


def crawl_source(
    source: CrawlSource,
    *,
    triggered_by=None,
    session=None,
    max_pages: int | None = None,
    respect_robots: bool = True,
    store_full_text: bool | None = None,
    dry_run: bool = False,
    skip_seen: bool = True,
) -> CrawlOutcome:
    """Run one crawl of one source and return what happened.

    `dry_run=True` runs the entire pipeline -- fetch, robots, extract, score,
    dedup, provenance -- and stops immediately before `_import_item`. Staging
    rows and `CrawlJob` counters are still written, because the whole point of
    a dry run is to show an administrator what a source *would* contribute. No
    `Story` or `Artifact` is created, and no item reaches `IMPORTED`.
    """
    if not source.enabled:
        raise ValueError(f'source {source.slug} is not enabled')

    job = CrawlJob.objects.create(
        source=source, triggered_by=triggered_by, status=CrawlJob.Status.RUNNING
    )
    outcome = CrawlOutcome(job=job, dry_run=dry_run)
    session = session or fetching.build_session(fetching.DEFAULT_USER_AGENT)
    allowed = source.domain_allowlist()
    page_budget = max_pages if max_pages is not None else source.max_pages
    store_full = source.allow_media_download if store_full_text is None else store_full_text

    queue = list(_seed_urls(source))
    visited: set[str] = set()

    # §17: incremental crawling. URLs this source already processed in an
    # earlier run are not downloaded again. Seed URLs are deliberately left out
    # of that set and always re-fetched: they are the entry points that link to
    # anything new, so skipping them would make every re-crawl reach exactly
    # what the last one reached -- which is the situation this fixes, not the
    # one it creates. `skip_seen=False` (the CLI's `--fresh`) ignores the set
    # entirely.
    already_processed: set[str] = set()
    if skip_seen:
        already_processed = set(
            CrawledItem.objects.filter(
                source=source, processing_status__in=_DEDUPABLE_STATUSES
            ).values_list('url_hash', flat=True)
        )
        for seed in queue:
            try:
                already_processed.discard(fetching.url_hash(seed))
            except FetchError:
                pass

    try:
        while queue and job.pages_processed < page_budget:
            url = queue.pop(0)
            try:
                key = fetching.url_hash(url)
            except FetchError as exc:
                log.warning('skipping unusable URL %r: %s', url, exc)
                outcome.skipped += 1
                continue
            if key in visited:
                continue
            if key in already_processed:
                # Downloaded and staged by an earlier job; do not fetch it
                # again. Counted so the operator can see how much a re-crawl
                # skipped, rather than wondering why it did so little.
                outcome.already_processed += 1
                continue
            visited.add(key)

            item = CrawledItem.objects.create(
                job=job,
                source=source,
                original_url=url,
                url_hash=key,
                processing_status=CrawledItem.ProcessingStatus.DISCOVERED,
            )
            outcome.item_ids.append(item.id)
            job.pages_processed += 1
            # Persist the counter, like every other one on the job. It used to
            # be incremented only on the in-memory object: the CLI's own report
            # printed the real number, while the administrator's job list, the
            # API and §16's monitoring summary all read 0 from the database.
            # Found by running a real crawl and re-reading the job in a fresh
            # process -- the in-process view cannot show this class of bug.
            job.save(update_fields=['pages_processed'])

            try:
                result = fetching.fetch(
                    url,
                    allowed_domains=allowed,
                    request_delay=source.request_delay,
                    timeout=source.timeout,
                    max_bytes=source.max_response_bytes,
                    session=session,
                    respect_robots=respect_robots,
                )
            except FetchError as exc:
                _record_error(item, exc)
                outcome.errors += 1
                job.errors += 1
                job.save(update_fields=['errors'])
                continue

            item.processing_status = CrawledItem.ProcessingStatus.FETCHED
            item.save(update_fields=['processing_status', 'updated_at'])

            try:
                page = extract_page(result.text, result.final_url)
            except Exception as exc:  # noqa: BLE001 - recorded, not swallowed
                _record_error(item, exc)
                outcome.errors += 1
                job.errors += 1
                job.save(update_fields=['errors'])
                continue

            item.processing_status = CrawledItem.ProcessingStatus.EXTRACTED
            item.extracted_title = page.title
            item.extracted_alt_title = page.alt_title
            item.extracted_description = page.description
            item.extracted_content = _preview(page.body_text)
            item.extracted_metadata = {
                'author': page.author,
                'institution': page.institution,
                'publication_date': page.publication_date,
                'language': page.language,
                'headings': page.headings,
                'licence_hint': page.metadata.get('licence', ''),
                'canonical_url': page.metadata.get('canonical_url', ''),
            }
            item.save(
                update_fields=[
                    'processing_status',
                    'extracted_title',
                    'extracted_alt_title',
                    'extracted_description',
                    'extracted_content',
                    'extracted_metadata',
                    'updated_at',
                ]
            )

            relevance = score_page(
                title=page.title,
                description=page.description,
                body=page.body_text,
                url=result.final_url,
            )
            # Persist the score *before* the relevance gate. It used to be
            # written only on the skip branch, so every page that passed the
            # gate reached the admin review queue with `relevance_score = 0.0`
            # and no reasons -- which is precisely what a reviewer needs in
            # order to judge the item, and what made `crawl --dry-run` print
            # blank scores. Found by running a real crawl: the queue was full
            # of 0.0 scores for pages that had actually scored well.
            item.relevance_score = relevance.score
            item.relevance_reasons = relevance.reasons
            item.save(
                update_fields=['relevance_score', 'relevance_reasons', 'updated_at']
            )
            job.items_found += 1
            job.save(update_fields=['items_found'])

            if not is_relevant(relevance, source.relevance_threshold):
                item.processing_status = CrawledItem.ProcessingStatus.SKIPPED
                item.save(
                    update_fields=['relevance_score', 'relevance_reasons',
                                   'processing_status', 'updated_at']
                )
                outcome.skipped += 1
                job.pages_skipped += 1
                job.save(update_fields=['pages_skipped'])
                # A page we are not importing still links to pages we might:
                # §3 lists discovery as a pipeline stage in its own right, and
                # skipping it here meant a crawl only ever expanded from pages
                # it had already accepted.
                _discover(queue, visited, page_budget, source, result)
                continue

            if not page.title:
                item.processing_status = CrawledItem.ProcessingStatus.SKIPPED
                item.save(update_fields=['processing_status', 'updated_at'])
                outcome.skipped += 1
                job.pages_skipped += 1
                job.save(update_fields=['pages_skipped'])
                _discover(queue, visited, page_budget, source, result)
                continue

            normalized = normalize_page(
                page, relevance, store_full_text=store_full
            )

            item.extracted_metadata = {
                **item.extracted_metadata,
                **normalized.as_metadata(),
            }
            item.processing_status = CrawledItem.ProcessingStatus.NORMALIZED
            item.save(
                update_fields=['extracted_metadata', 'processing_status', 'updated_at']
            )

            # --- Duplicate detection (§10) -----------------------------------
            duplicate = _find_duplicate(
                source, normalized.fingerprint, result.final_url, exclude_pk=item.pk
            )
            if duplicate is not None:
                item.processing_status = CrawledItem.ProcessingStatus.DUPLICATE
                item.save(
                    update_fields=['processing_status', 'updated_at']
                )
                _record_cross_source_reference(item, source, duplicate, page)
                outcome.duplicates += 1
                job.duplicates_found += 1
                job.save(update_fields=['duplicates_found'])
                _discover(queue, visited, page_budget, source, result)
                continue

            # --- Provenance, then import (§5, §3) ----------------------------
            reference = SourceReference.objects.create(
                item=item,
                source=source,
                original_url=result.final_url,
                author=page.author,
                institution=page.institution,
                publication_date=page.publication_date or None,
                crawled_at=timezone.now(),
                extraction_method=(
                    SourceReference.ExtractionMethod.FULL_TEXT
                    if store_full
                    else SourceReference.ExtractionMethod.METADATA_ONLY
                ),
                licence=source.default_licence,
                attribution=page.institution or page.author or '',
                confidence_score=relevance.score,
                # We stored an excerpt, not the whole page.
                extracted_verbatim=False,
            )

            if dry_run:
                # Everything above this line is real; this is the only place
                # the corpus is written, so this is the only place a dry run
                # has to stop.
                #
                # The `continue` used to sit here, which also skipped the
                # discovery block below -- so a dry run never followed a single
                # link and reported only the seed URLs, which made `--dry-run`
                # useless for the one thing it exists to answer: what a deeper
                # crawl would actually reach. Discovery now runs on both paths.
                item.save(update_fields=['updated_at'])
                outcome.media_recorded += _record_media(item, source, page, reference)
                _discover(queue, visited, page_budget, source, result)
                continue

            _import_item(item, source, normalized, reference, page)
            outcome.imported += 1
            job.items_imported += 1
            job.save(update_fields=['items_imported'])

            # --- Media (§6, §7): record always, download only if licensed ----
            recorded = _record_media(item, source, page, reference)
            outcome.media_recorded += recorded

            # --- Discovery --------------------------------------------------
            _discover(queue, visited, page_budget, source, result)

        job.status = (
            CrawlJob.Status.COMPLETED_WITH_ERRORS
            if job.errors
            else CrawlJob.Status.COMPLETED
        )
    except Exception:  # noqa: BLE001 - a job-level failure still records itself
        log.exception('crawl job %s failed', job.pk)
        job.status = CrawlJob.Status.FAILED
        job.notes = 'Job aborted; see logs.'
        outcome.errors += 1
        job.errors += 1
    finally:
        job.completed_at = timezone.now()
        job.save(update_fields=['status', 'completed_at', 'errors', 'notes'])

    return outcome


def _discover(queue, visited, page_budget, source: CrawlSource, result) -> None:
    """Queue the links found on `result`, respecting depth and the page budget.

    Module-level rather than inlined so every path that reaches it discovers
    identically: the import path, the dry-run path, and the skip/duplicate/
    no-title paths. Each of those used to `continue` before discovery, so a
    crawl only expanded from the pages it had already accepted -- a source
    whose single seed was irrelevant or already imported discovered nothing at
    all, and a re-crawl reached exactly what the last one did.
    """
    if source.max_depth <= 0:
        return
    if len(queue) + len(visited) >= page_budget:
        return
    queue.extend(
        fetching.discover_urls(
            result.text,
            result.final_url,
            include_patterns=source.include_url_patterns,
            exclude_patterns=source.exclude_url_patterns,
            max_depth=source.max_depth,
        )
    )


def _preview(text: str, limit: int = 600) -> str:
    """Short excerpt kept on the staging row for reviewer eyeballing."""
    collapsed = ' '.join(text.split())
    return collapsed[:limit]


#: Which statuses count as "already processed" for duplicate detection.
#:
#: `NORMALIZED` is included as well as `IMPORTED`. It used to be IMPORTED alone,
#: which meant duplicate detection was inert during a dry run -- a dry run never
#: reaches IMPORTED, so `--dry-run` reported "Duplicates: 0" no matter how many
#: times it fetched the same page. On the UNESCO source the same element is
#: linked both as `/en/RL/ngondo-...-02140` and `/en/RL/ngondo-...-02140?RL=02140`,
#: so the query-string variant was fetched, staged and counted as new content.
#: That is exactly the case §10 asks to catch, and the count was structurally
#: incapable of being anything but zero.
#:
#: These are plain strings used with `__in`, never enum members passed as a
#: tuple. Django reads `field=(a, b)` as `field = (a, b)` -- an equality
#: test against a tuple, not a membership test -- which matches nothing and
#: returns no error. That is a silent, total failure of duplicate detection
#: that looks exactly like a site with no repeated content.
_DEDUPABLE_STATUSES = (
    CrawledItem.ProcessingStatus.IMPORTED.value,
    CrawledItem.ProcessingStatus.NORMALIZED.value,
)


def _find_duplicate(
    source: CrawlSource, fingerprint: str, url: str, *, exclude_pk=None
):
    """Return an existing `CrawledItem` this one duplicates, or None.

    §10 asks for three comparisons -- URL, normalised title, and content
    similarity -- and to preserve all sources when a match is found. The
    ordering matters:

    1. **Identical URL from this source** — the same page reached twice, by a
       re-crawl or a `max_depth` re-discovery. Cheap, exact, and checked first.
    2. **Identical content fingerprint, any source** — the same text. The
       fingerprint is a hash of the normalised title and body, so this matches
       republication rather than shared subject matter: two museums writing
       their own paragraphs about the same mask produce different fingerprints
       and both get imported, which is what §10 means by "do not treat
       different sources as duplicates merely because they describe the same
       cultural subject".

    When the match came from a different source the caller records an extra
    `SourceReference` instead of importing a second copy, so the item keeps both
    provenance rows and a reviewer can see the republication.

    `exclude_pk` is the item currently being processed. It has already been
    saved as NORMALIZED with its own fingerprint by the time this runs, so
    without the exclusion every item matched itself and was recorded as a
    duplicate of itself -- which reads as "this import works" in a test and
    produces no second record in production, hiding the fact that nothing was
    ever deduplicated at all.

    An earlier version only ever searched within one source, which meant the
    cross-source branch in the caller was unreachable -- the docstring described
    behaviour the code did not have, and identical text on two authoritative
    hosts produced two reader-facing records for one heritage item.
    """
    # Cheap exact guard first.
    try:
        key = fetching.url_hash(url)
    except FetchError:
        key = None

    if key is not None:
        same_url = (
            CrawledItem.objects.filter(
                source=source,
                url_hash=key,
                processing_status__in=_DEDUPABLE_STATUSES,
            )
            .only('id', 'extracted_metadata')
            .exclude(pk=exclude_pk)
            .first()
        )
        if same_url is not None:
            return same_url

    # Content fingerprint, across all sources. A key transform on the JSON
    # field rather than a SQL LIKE: the LIKE version matched the JSON
    # *serialisation*, so it broke on any Django version that changed the
    # separator spacing, and it was not portable off SQLite.
    return (
        CrawledItem.objects.filter(
            processing_status__in=_DEDUPABLE_STATUSES,
            extracted_metadata__fingerprint=fingerprint,
        )
        .only('id', 'extracted_metadata')
        .exclude(pk=exclude_pk)
        .first()
    )


def _record_cross_source_reference(item, source, existing, page) -> None:
    """A second source describing the same page: keep both provenance records."""
    SourceReference.objects.get_or_create(
        item=existing,
        source=source,
        original_url=item.original_url,
        defaults={
            'author': page.author,
            'institution': page.institution,
            'confidence_score': item.relevance_score,
            'extracted_verbatim': False,
        },
    )


#: Account that owns crawled Stories. See `crawler_account` for why.
CRAWLER_ACCOUNT_USERNAME = 'heritage-crawler'


def crawler_account():
    """Get-or-create the service account that owns crawled Stories.

    `Story.author` is a required FK and is dereferenced unconditionally elsewhere
    (`stories/views.py` renders `story.author.username` in the moderation
    dashboard), so a NULL author is not an option. An earlier version of this
    module simply omitted `author`, and every page the classifier read as a
    *story* -- legends, folktales, oral traditions, which is most of what §2
    asks for -- died on `IntegrityError` and took the whole crawl job down with
    it. A mask fixture classified as an Artefact and hid the defect entirely.

    The account is inactive and unusable for login; it exists so that ownership
    is answerable. The real authorship of a crawled story is the *source*, and
    that is recorded properly on `SourceReference` (author, institution,
    original URL) rather than being faked onto a user row.
    """
    from django.contrib.auth import get_user_model

    User = get_user_model()
    account, _created = User.objects.get_or_create(
        username=CRAWLER_ACCOUNT_USERNAME,
        defaults={
            'email': '',
            'role': 'contributor',
            'is_active': False,
            'is_staff': False,
            'is_superuser': False,
            'first_name': 'Heritage',
            'last_name': 'Crawler',
        },
    )
    # Keep it unusable even if someone edits it later by hand.
    #
    # The password matters as much as the flags. `User.objects.create` runs
    # `set_unusable_password`, but `get_or_create`'s `create` path goes through
    # the same manager and leaves an *empty* password -- and `AbstractBaseUser`
    # treats '' as usable, so `has_usable_password()` returned True and the
    # account was one password-less form submit away from being logged into.
    # Inactive is the real defence; this closes the second door.
    changed = False
    if account.is_active or account.is_staff or account.is_superuser:
        account.is_active = False
        account.is_staff = False
        account.is_superuser = False
        changed = True
    if account.has_usable_password():
        account.set_unusable_password()
        changed = True
    if changed:
        account.save(
            update_fields=['is_active', 'is_staff', 'is_superuser', 'password']
        )
    return account


def _import_item(item: CrawledItem, source: CrawlSource, normalized, reference, page):
    """Create the Story or Artifact this item became — always pending review."""
    from qr_codes.models import Artifact
    from stories.models import Story

    # Resolve the slug against both tables. A museum's collection index and the
    # item it lists very often share a title, and `slug` is unique on both
    # models -- so an un-uniquified slug raises IntegrityError here, outside the
    # per-page error boundary, and takes the whole crawl job down with it.
    def _slug_taken(candidate: str) -> bool:
        return (
            Story.objects.filter(slug=candidate).exists()
            or Artifact.objects.filter(slug=candidate).exists()
        )

    slug = unique_slug(normalized.title, fallback='heritage-item', exists=_slug_taken)

    with transaction.atomic():
        if normalized.kind == 'artifact':
            artifact = Artifact.objects.create(
                title=normalized.title[:200],
                slug=slug[:250],
                description=normalized.summary,
                category=normalized.category or 'other',
                content_type=normalized.content_type or 'unknown',
                culture=normalized.cultural_group,
                region=normalized.region,
                museum_name=normalized.museum_name[:200],
                source_url=item.original_url,
                is_published=False,  # §13: never publish from a crawl.
            )
            item.mark_imported(artifact=artifact)
        else:
            story = Story.objects.create(
                author=crawler_account(),
                title=normalized.title[:200],
                slug=slug[:250],
                content=normalized.content,
                summary=normalized.summary,
                region=normalized.region,
                tags=', '.join(normalized.tags)[:200],
                source=reference.institution or source.name,
                origin=Story.Origin.PUBLISHED_COLLECTION,
                licence=source.default_licence,
                status=Story.Status.PENDING,  # §3: PENDING_REVIEW, not published.
                provenance_notes=_provenance_note(source, reference, normalized),
            )
            item.mark_imported(story=story)


def _provenance_note(source: CrawlSource, reference, normalized) -> str:
    """A human-readable provenance block for the story's own field.

    §21 wants the administrator to be able to see the original source and to
    tell extracted text from system reasoning. The structured version lives on
    `SourceReference`; this is the version a person actually reads in the admin.
    """
    lines = [
        f'Imported by the heritage crawler from {source.name} ({source.base_url}).',
        f'Original page: {reference.original_url}',
        f'Extraction: {reference.get_extraction_method_display()} '
        f'(relevance {reference.confidence_score:.2f}).',
    ]
    if reference.author:
        lines.append(f'Author as stated by the source: {reference.author}')
    if reference.institution:
        lines.append(f'Institution: {reference.institution}')
    if reference.publication_date:
        lines.append(f'Publication date as stated: {reference.publication_date}')
    if normalized.inferred_fields:
        lines.append(
            'System-inferred, NOT stated by the source — verify before approving: '
            + ', '.join(normalized.inferred_fields)
        )
    return '\n'.join(lines)


def _record_media(item: CrawledItem, source: CrawlSource, page, reference) -> int:
    """Record media on the item. Download only when reuse is permitted."""
    created = 0
    for image in page.images:
        media = CrawlMedia.objects.create(
            item=item,
            media_type=CrawlMedia.MediaType.IMAGE,
            original_url=image['url'][:1000],
            attribution=reference.attribution,
            alt_text=image.get('alt', '')[:300],
            licence=source.default_licence,
            reused=bool(source.allow_media_download),
        )
        if source.allow_media_download:
            _download_media(media, source)
        created += 1

    for document in page.documents:
        CrawlMedia.objects.create(
            item=item,
            media_type=CrawlMedia.MediaType.DOCUMENT,
            original_url=document['url'][:1000],
            attribution=reference.attribution,
            licence=source.default_licence,
            reused=False,
        )
        created += 1
    return created


def _download_media(media: CrawlMedia, source: CrawlSource) -> None:
    """Fetch one media file, with the same guards as a page fetch.

    §20: validate file type, cap size, sanitize filenames, never execute
    downloaded code. Media lands under MEDIA_ROOT with a sanitised name; a
    failure leaves `local_path` empty rather than recording a broken path.
    """
    import mimetypes
    import os

    from django.conf import settings
    from django.utils.crypto import get_valid_filename

    session = fetching.build_session(fetching.DEFAULT_USER_AGENT)
    try:
        fetching.assert_safe_url(media.original_url, source.domain_allowlist())
        result = fetching.fetch(
            media.original_url,
            allowed_domains=source.domain_allowlist(),
            request_delay=source.request_delay,
            timeout=source.timeout,
            max_bytes=source.max_response_bytes,
            session=session,
            # robots.txt governs pages; a media asset inherits the same policy
            # decision the source made when it was enabled.
            respect_robots=False,
        )
    except FetchError as exc:
        log.warning('media download failed for %s: %s', media.original_url, exc)
        return

    media.mime_type = result.content_type.split(';')[0].strip()
    media.file_size = len(result.text.encode('utf-8', errors='ignore'))
    media.checksum = _checksum(result.text)

    extension = mimetypes.guess_extension(media.mime_type) or '.bin'
    base = get_valid_filename(
        os.path.splitext(os.path.basename(media.original_url))[0]
    )[:80] or 'media'
    relative = os.path.join('heritage_crawl', f'{base}{extension}')
    absolute = os.path.join(settings.MEDIA_ROOT, relative)

    try:
        os.makedirs(os.path.dirname(absolute), exist_ok=True)
        with open(absolute, 'w', encoding='utf-8') as handle:
            handle.write(result.text)
    except OSError as exc:
        log.warning('could not write %s: %s', absolute, exc)
        return

    media.local_path = relative
    media.save(update_fields=['mime_type', 'file_size', 'checksum', 'local_path'])


def _checksum(value: str) -> str:
    import hashlib

    return hashlib.sha256(value.encode('utf-8', errors='ignore')).hexdigest()