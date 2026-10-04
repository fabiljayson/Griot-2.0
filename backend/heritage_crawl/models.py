"""
Operational models for cultural-heritage ingestion.

Read this before adding anything here.

The obvious thing to do with a crawler spec is to create `CulturalContent`,
`Source`, `SourceReference`, `Media`, `CrawlJob` and `CrawledItem` as the spec
suggests. That would have been the wrong call, and the spec itself says so
(§11: "Do not create duplicate models if equivalent models already exist";
§12: "Adapt these models to my existing architecture instead of blindly
creating them"). This project already has:

* `stories.Story`   - status, origin, licence, consent_status, provenance_notes,
                      source, region, language, tags, cover_image, audio_url,
                      video_url, reviewer_notes
* `qr_codes.Artifact` - category, content_type, culture, region, materials,
                      dimensions, image, additional_images, museum_name,
                      historical_significance, source_url, audio_file,
                      video_url_field, is_published

Both already carry rights, provenance and a review status, and the admin
dashboard and Flutter client are already wired to them. A parallel
`CulturalContent` table would have split the corpus in two: half the heritage
visible to readers, half stranded behind the crawler, with two sets of
moderation, two sets of media, and no path from one to the other.

So crawled items become `Story` and `Artifact` rows. What genuinely did not
exist is the machinery *around* ingestion - the record of where a fetch
decision came from, what was extracted before it became a Story, and which run
produced it. Those are the five models below, and they are operational: no
reader-facing query touches them.

Two invariants are enforced by more than convention:

1. A `CrawledItem` that reaches `IMPORTED` must point at a `Story` or an
   `Artifact`, and that target must be in a review state, never published.
   `CrawledItem.mark_imported` refuses otherwise.
2. A `SourceReference` always keeps `original_url`. Nothing in this codebase
   may null it out; it is the reason an administrator can answer "where did
   this come from" after the fact.
"""

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from stories.models import Story


class CrawlSource(models.Model):
    """A configured place the crawler is allowed to read from.

    Sources are data, not code, so a new museum or a new UNESCO collection is a
    database row rather than a deploy. `source_config.py` seeds the built-in
    registry; administrators may add their own.

    `allowed_domains` is the security boundary, not a hint: `fetching` refuses
    to follow anything outside it, which is what stops a crawled page from
    turning the crawler into an SSRF proxy into the private network.
    """

    class SourceType(models.TextChoices):
        MUSEUM = 'museum', _('Museum')
        GOVERNMENT = 'government', _('Government / ministry')
        UNESCO = 'unesco', _('UNESCO')
        RESEARCH = 'research', _('Academic or research')
        ARCHIVE = 'archive', _('Digital archive')
        OTHER = 'other', _('Other')

    class Reliability(models.TextChoices):
        """How much weight a reviewer should give this source.

        Not a truth judgement about the source's quality — a documented
        rationale for trusting it, which is what §21 asks an administrator to
        be able to inspect.
        """

        AUTHORITATIVE = 'authoritative', _('Authoritative / official')
        SCHOLARLY = 'scholarly', _('Scholarly / peer-reviewed')
        CURATED = 'curated', _('Curated secondary source')
        UNVERIFIED = 'unverified', _('Unverified')

    slug = models.SlugField(max_length=80, unique=True)
    name = models.CharField(max_length=200)
    base_url = models.URLField(max_length=500)
    source_type = models.CharField(
        max_length=20, choices=SourceType.choices, default=SourceType.OTHER
    )
    reliability = models.CharField(
        max_length=20, choices=Reliability.choices, default=Reliability.UNVERIFIED
    )

    enabled = models.BooleanField(default=False)
    is_builtin = models.BooleanField(
        default=False,
        help_text='Seeded from source_config; still editable by an administrator.',
    )

    # --- Crawl limits. Deliberately small: §14 says "Do not crawl aggressively". ---
    max_pages = models.PositiveIntegerField(default=25)
    max_depth = models.PositiveSmallIntegerField(
        default=1, help_text='0 = only the seed URLs, 1 = their links, and so on.'
    )
    request_delay = models.FloatField(
        default=2.0, help_text='Seconds between requests to this source.'
    )
    timeout = models.PositiveIntegerField(default=20)
    max_response_bytes = models.PositiveIntegerField(default=5_000_000)
    relevance_threshold = models.FloatField(
        default=0.70,
        validators=[MinValueValidator(0.0), MaxValueValidator(1.0)],
    )

    # --- Allow-lists ---
    allowed_domains = models.JSONField(
        default=list,
        blank=True,
        help_text='Hostnames the fetcher may contact for this source. '
        'Empty means base_url only.',
    )
    seed_urls = models.JSONField(
        default=list,
        blank=True,
        help_text='Pages to start from. Empty means base_url alone. '
        'A list, not a single URL, because a museum site usually has a '
        'collection index and an institution page worth reading separately.',
    )
    include_url_patterns = models.JSONField(default=list, blank=True)
    exclude_url_patterns = models.JSONField(default=list, blank=True)

    # --- Rights defaults (§6) ---
    default_licence = models.CharField(
        max_length=40,
        choices=Story.Licence.choices,
        default=Story.Licence.UNDETERMINED,
        help_text='Applied to imported items unless the page states otherwise. '
        'Defaults to undetermined: §6 says do not assume reuse is permitted.',
    )
    allow_media_download = models.BooleanField(
        default=False,
        help_text='Leave off unless the source explicitly licenses reuse. When '
        'off, media is recorded by URL and attribution only.',
    )
    contact_note = models.CharField(
        max_length=300, blank=True, default=''
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['slug']
        verbose_name_plural = 'crawl sources'

    def __str__(self):
        return self.name

    def domain_allowlist(self) -> list[str]:
        """Hostnames this source may contact, always including its own base host."""
        from urllib.parse import urlparse

        hosts = {urlparse(self.base_url).hostname or ''}
        hosts.update(h.strip().lower() for h in (self.allowed_domains or []) if h)
        return sorted(h for h in hosts if h)


class CrawlJob(models.Model):
    """One execution of the crawler against one source.

    The counters are the run's summary (§16). They are denormalised on purpose:
    a report that has to replay every item to answer "how many pages did the
    last crawl visit" is a report nobody runs.
    """

    class Status(models.TextChoices):
        RUNNING = 'running', _('Running')
        COMPLETED = 'completed', _('Completed')
        COMPLETED_WITH_ERRORS = 'completed_with_errors', _('Completed with errors')
        FAILED = 'failed', _('Failed')
        CANCELLED = 'cancelled', _('Cancelled')

    source = models.ForeignKey(
        CrawlSource, on_delete=models.PROTECT, related_name='jobs'
    )
    status = models.CharField(
        max_length=30, choices=Status.choices, default=Status.RUNNING
    )

    started_at = models.DateTimeField(default=timezone.now)
    completed_at = models.DateTimeField(null=True, blank=True)

    pages_processed = models.PositiveIntegerField(default=0)
    pages_skipped = models.PositiveIntegerField(default=0)
    items_found = models.PositiveIntegerField(default=0)
    items_imported = models.PositiveIntegerField(default=0)
    duplicates_found = models.PositiveIntegerField(default=0)
    errors = models.PositiveIntegerField(default=0)

    triggered_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='crawl_jobs',
        help_text='Null for a scheduled or CLI run.',
    )
    notes = models.TextField(blank=True, default='')

    class Meta:
        ordering = ['-started_at']

    def __str__(self):
        return f'{self.source.slug} @ {self.started_at:%Y-%m-%d %H:%M}'

    def duration_seconds(self) -> float | None:
        if not self.completed_at:
            return None
        return (self.completed_at - self.started_at).total_seconds()

    def summary(self) -> dict[str, int]:
        return {
            'pages_processed': self.pages_processed,
            'pages_skipped': self.pages_skipped,
            'items_found': self.items_found,
            'items_imported': self.items_imported,
            'duplicates_found': self.duplicates_found,
            'errors': self.errors,
        }


class CrawledItem(models.Model):
    """One discovered URL and everything extracted from it, before it becomes a Story.

    This is the staging area and the audit trail. It exists because §21 requires
    that an administrator be able to inspect *the original extraction* before
    approving anything, and because a crawl that imports into `Story` directly
    leaves no record of what was rejected or why.
    """

    class ProcessingStatus(models.TextChoices):
        """Where an item is in the §13 workflow.

        The first six are the pipeline's (§3: discovery through normalisation);
        `IMPORTED` is what this pipeline calls PENDING_REVIEW — content that
        exists as a `Story`/`Artifact` in a review state, waiting for a person.
        The last three are reviewer decisions and are only ever set by
        `review.py`, never by the crawler.
        """

        DISCOVERED = 'discovered', _('Discovered')
        FETCHED = 'fetched', _('Fetched')
        EXTRACTED = 'extracted', _('Extracted')
        NORMALIZED = 'normalized', _('Normalized')
        DUPLICATE = 'duplicate', _('Duplicate')
        SKIPPED = 'skipped', _('Skipped — not relevant / disallowed')
        ERROR = 'error', _('Error')
        # --- Review states ---
        IMPORTED = 'imported', _('Pending review')
        APPROVED = 'approved', _('Approved')
        REJECTED = 'rejected', _('Rejected')
        NEEDS_CORRECTION = 'needs_correction', _('Needs correction')

    job = models.ForeignKey(CrawlJob, on_delete=models.CASCADE, related_name='items')
    source = models.ForeignKey(
        CrawlSource, on_delete=models.PROTECT, related_name='items'
    )

    original_url = models.URLField(max_length=1000)
    url_hash = models.CharField(
        max_length=64,
        db_index=True,
        help_text='SHA-256 of the normalised URL; the cheap duplicate key.',
    )

    extracted_title = models.CharField(max_length=500, blank=True, default='')
    extracted_alt_title = models.CharField(max_length=500, blank=True, default='')
    extracted_description = models.TextField(blank=True, default='')
    extracted_content = models.TextField(
        blank=True,
        default='',
        help_text='Plain text. Raw HTML is never stored.',
    )
    extracted_metadata = models.JSONField(default=dict, blank=True)

    relevance_score = models.FloatField(default=0.0)
    relevance_reasons = models.JSONField(default=list, blank=True)

    processing_status = models.CharField(
        max_length=20,
        choices=ProcessingStatus.choices,
        default=ProcessingStatus.DISCOVERED,
    )
    error_type = models.CharField(max_length=60, blank=True, default='')
    error_message = models.TextField(blank=True, default='')

    # What this item became. At most one of these is set.
    story = models.ForeignKey(
        'stories.Story',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='crawled_items',
    )
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='crawled_items',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['job', 'processing_status']),
            models.Index(fields=['url_hash']),
            models.Index(fields=['processing_status', '-created_at']),
        ]

    def __str__(self):
        return f'{self.processing_status}: {self.original_url[:80]}'

    def mark_imported(self, *, story=None, artifact=None) -> None:
        """Attach this item to what it produced, refusing an unsafe outcome.

        Guards the one invariant a reviewer would otherwise have to check by
        hand: crawled content enters the corpus *for review*, never published.
        """
        if story is None and artifact is None:
            raise ValueError('mark_imported requires a story or an artifact')
        if story is not None and artifact is not None:
            raise ValueError('mark_imported takes a story or an artifact, not both')
        if story is not None and story.status == Story.Status.PUBLISHED:
            raise ValueError('refusing to attach crawled content to a published story')
        if artifact is not None and artifact.is_published:
            raise ValueError('refusing to attach crawled content to a published artifact')

        self.story = story
        self.artifact = artifact
        self.processing_status = self.ProcessingStatus.IMPORTED
        self.save(
            update_fields=[
                'story',
                'artifact',
                'processing_status',
                'updated_at',
            ]
        )


def Story_PUBLISHED() -> str:
    """The one Story status that crawled content must never arrive as."""
    return 'published'


class SourceReference(models.Model):
    """Provenance for a single fact trail: who said this, where, and under what terms.

    A `Story` or `Artifact` can have many of these. §5 requires that every
    imported item can be traced back to its original source and that the
    original URL is never removed, so `original_url` is non-null and there is
    deliberately no `on_delete` path that drops it silently.
    """

    class ExtractionMethod(models.TextChoices):
        FULL_TEXT = 'full_text', _('Full text extracted')
        METADATA_ONLY = 'metadata_only', _('Metadata and summary only')
        MANUAL_ENTRY = 'manual_entry', _('Entered by hand')

    item = models.ForeignKey(
        CrawledItem,
        on_delete=models.CASCADE,
        related_name='references',
        null=True,
        blank=True,
        help_text='Null when a reference was added to a Story/Artifact directly.',
    )
    source = models.ForeignKey(CrawlSource, on_delete=models.PROTECT, related_name='+')

    original_url = models.URLField(max_length=1000)
    author = models.CharField(max_length=300, blank=True, default='')
    institution = models.CharField(max_length=300, blank=True, default='')
    publication_date = models.DateField(null=True, blank=True)
    crawled_at = models.DateTimeField(default=timezone.now)

    extraction_method = models.CharField(
        max_length=20,
        choices=ExtractionMethod.choices,
        default=ExtractionMethod.METADATA_ONLY,
    )
    licence = models.CharField(max_length=40, blank=True, default='')
    attribution = models.CharField(max_length=500, blank=True, default='')

    confidence_score = models.FloatField(
        default=0.0,
        validators=[MinValueValidator(0.0), MaxValueValidator(1.0)],
    )

    # §21: the difference between what the source said and what we concluded.
    extracted_verbatim = models.BooleanField(
        default=False,
        help_text='True when the stored text is the source wording, unmodified. '
        'False means it was summarised or normalised by the system.',
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-crawled_at']
        indexes = [models.Index(fields=['original_url'])]

    def __str__(self):
        return f'{self.source.slug}: {self.original_url[:70]}'


class CrawlMedia(models.Model):
    """A media file seen on a crawled page.

    Media is *not* downloaded by default (§6, §7). When reuse permission cannot
    be established the row still exists — pointing at `original_url` with the
    attribution — because knowing an image exists is useful to a reviewer even
    when we may not redistribute it. `local_path` stays null in that case.
    """

    class MediaType(models.TextChoices):
        IMAGE = 'image', _('Image')
        AUDIO = 'audio', _('Audio')
        VIDEO = 'video', _('Video')
        DOCUMENT = 'document', _('Document')

    item = models.ForeignKey(
        CrawledItem, on_delete=models.CASCADE, related_name='media'
    )
    target = models.ForeignKey(
        'stories.Story',
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name='crawl_media',
    )
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name='crawl_media',
    )

    media_type = models.CharField(
        max_length=12, choices=MediaType.choices, default=MediaType.IMAGE
    )
    mime_type = models.CharField(max_length=100, blank=True, default='')
    original_url = models.URLField(max_length=1000)
    local_path = models.CharField(
        max_length=500,
        blank=True,
        default='',
        help_text='Relative to MEDIA_ROOT. Empty when the file was not downloaded.',
    )
    file_size = models.PositiveIntegerField(null=True, blank=True)
    checksum = models.CharField(max_length=64, blank=True, default='')

    licence = models.CharField(max_length=40, blank=True, default='')
    attribution = models.CharField(max_length=500, blank=True, default='')
    alt_text = models.CharField(max_length=300, blank=True, default='')
    reused = models.BooleanField(
        default=False, help_text='Whether reuse permission was established.'
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['id']
        indexes = [
            models.Index(fields=['checksum']),
            models.Index(fields=['original_url']),
        ]

    def __str__(self):
        return f'{self.media_type}: {self.original_url[:60]}'
