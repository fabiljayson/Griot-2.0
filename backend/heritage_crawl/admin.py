"""
Admin surface for the crawler.

§13 lists what an administrator must be able to do — view the imported
content, view the original source, view the extracted information, view
downloaded media, edit metadata, approve, reject, request correction, remove —
and this module is where that list becomes buttons.

The workflow it implements is the spec's:

    CRAWLED -> EXTRACTED -> NORMALIZED -> PENDING_REVIEW -> APPROVED -> PUBLISHED

with REJECTED and NEEDS_CORRECTION as the exits. The crawler itself only ever
produces the first three states plus `IMPORTED` (which *is* this pipeline's
`PENDING_REVIEW`: content sitting in `Story`/`Artifact` as `pending`, awaiting a
human). Everything past that is a deliberate act by an administrator, and each
transition here records who did it and why.

Two design notes worth stating, because they look like omissions:

* **Approval is deliberately not one click.** `_approve` refuses to publish an
  item whose provenance is missing a usable original URL. §5 says the database
  must allow tracing every imported item back to its source; approving content
  we cannot trace would quietly break that for readers.
* **Rejection does not delete.** §13 asks for both "reject" and "remove", which
  are different acts: rejection keeps the audit trail, removal discards it.
  They are separate actions here so an administrator chooses deliberately.
"""

from django.contrib import admin, messages

from .models import CrawledItem, CrawlJob, CrawlMedia, CrawlSource, SourceReference
from .review import ReviewError, approve_item, reject, request_correction


@admin.register(CrawlSource)
class CrawlSourceAdmin(admin.ModelAdmin):
    """Configuration. A new museum is a row here, not a deploy."""

    list_display = (
        'name',
        'source_type',
        'reliability',
        'enabled',
        'is_builtin',
        'max_pages',
        'max_depth',
        'request_delay',
        'relevance_threshold',
        'allow_media_download',
    )
    list_filter = ('enabled', 'is_builtin', 'source_type', 'reliability')
    search_fields = ('name', 'slug', 'base_url')
    prepopulated_fields = {'slug': ('name',)}

    fieldsets = (
        (None, {
            'fields': ('name', 'slug', 'base_url', 'source_type', 'reliability'),
        }),
        # Nothing crawls until someone ticks this. Built-in sources seed
        # disabled precisely so that installing the app never produces
        # outbound traffic on its own.
        ('Activation', {
            'fields': ('enabled', 'is_builtin', 'contact_note'),
            'description': 'Crawling only runs for enabled sources. Built-in '
                           'sources ship disabled.',
        }),
        ('Crawl limits', {
            'fields': (
                'max_pages',
                'max_depth',
                'request_delay',
                'timeout',
                'max_response_bytes',
                'relevance_threshold',
            ),
        }),
        ('URL scope', {
            'fields': (
                'allowed_domains',
                'seed_urls',
                'include_url_patterns',
                'exclude_url_patterns',
            ),
            'description': 'allowed_domains is a security boundary, not a hint. '
                           'The fetcher refuses to contact anything outside it.',
        }),
        ('Rights', {
            'fields': ('default_licence', 'allow_media_download'),
            'description': 'Leave media download off unless the source '
                           'explicitly licenses reuse. §6.',
        }),
    )

    readonly_fields = ('created_at', 'updated_at')


@admin.register(CrawlJob)
class CrawlJobAdmin(admin.ModelAdmin):
    list_display = (
        'source',
        'status',
        'started_at',
        'completed_at',
        'duration_seconds',
        'pages_processed',
        'items_found',
        'items_imported',
        'duplicates_found',
        'errors',
    )
    list_filter = ('status', 'source__source_type', 'started_at')
    search_fields = ('source__name', 'source__slug')
    date_hierarchy = 'started_at'
    readonly_fields = (
        'source', 'status', 'started_at', 'completed_at', 'duration_seconds',
        'pages_processed', 'pages_skipped', 'items_found', 'items_imported',
        'duplicates_found',        'errors', 'triggered_by', 'summary_block',
    )


    fieldsets = (
        (None, {'fields': ('source', 'status', 'triggered_by',
                           'started_at', 'completed_at', 'duration_seconds')}),
        ('Counters (§16 summary)', {
            'fields': (
                'pages_processed', 'pages_skipped', 'items_found',
                'items_imported', 'duplicates_found', 'errors', 'summary_block',
            ),
        }),
        ('Notes', {'fields': ('notes',)}),
    )

    def has_add_permission(self, request):
        return False

    @admin.display(description='Summary')
    def summary_block(self, obj):
        """The §16 summary, rendered where a reviewer will actually look."""
        if obj is None or obj.pk is None:
            return '-'
        rows = '\n'.join(f'{k}: {v}' for k, v in obj.summary().items())
        return rows.replace('\n', '<br>')


class SourceReferenceInline(admin.TabularInline):
    """Provenance, shown inline so the reviewer never has to go looking."""

    model = SourceReference
    extra = 0
    show_change_link = True
    fields = ('source', 'original_url', 'author', 'institution',
              'publication_date', 'crawled_at', 'extraction_method',
              'licence', 'attribution', 'confidence_score', 'extracted_verbatim')
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):
        # Provenance is written by the ingestion layer. Hand-entered provenance
        # is a different (legitimate) thing and is added on the Story admin.
        return False


class CrawlMediaInline(admin.TabularInline):
    model = CrawlMedia
    extra = 0
    show_change_link = True
    fields = ('media_type', 'original_url', 'local_path', 'file_size',
              'checksum', 'licence', 'attribution', 'reused')
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(CrawledItem)
class CrawledItemAdmin(admin.ModelAdmin):
    """The review queue. This is the screen §13 is really about."""

    list_display = (
        'short_url',
        'extracted_title',
        'processing_status',
        'relevance_score',
        'source',
        'produced_target',
        'created_at',
    )
    list_filter = ('processing_status', 'source', 'job__status')
    search_fields = ('original_url', 'extracted_title', 'extracted_content')
    date_hierarchy = 'created_at'
    readonly_fields = (
        'job', 'source', 'original_url', 'url_hash',
        'extracted_title', 'extracted_alt_title', 'extracted_description',
        'extracted_content', 'extracted_metadata',
        'relevance_score', 'relevance_reasons',
        'processing_status', 'error_type', 'error_message',
        'story', 'artifact', 'provenance_link', 'created_at', 'updated_at',
    )
    actions = ('approve_items', 'reject_items', 'request_correction_items',
               'remove_items')
    list_select_related = ('job', 'source', 'story', 'artifact')
    inlines = [SourceReferenceInline, CrawlMediaInline]

    fieldsets = (
        # The original page is the first thing a reviewer opens, so it is the
        # first field. §21: the administrator must be able to inspect the
        # source before approving.
        ('Original source', {
            'fields': ('original_url', 'provenance_link', 'source', 'job'),
        }),
        ('What the extractor found', {
            'fields': (
                'extracted_title', 'extracted_alt_title', 'extracted_description',
                'extracted_content', 'extracted_metadata',
            ),
            'description': 'Verbatim extraction output. Shown read-only so the '
                           'record of what the system saw cannot drift from what '
                           'a reviewer approved.',
        }),
        ('Relevance', {
            'fields': ('relevance_score', 'relevance_reasons'),
        }),
        ('Outcome', {
            'fields': ('processing_status', 'story', 'artifact'),
        }),
        ('Errors', {'fields': ('error_type', 'error_message'),
                    'classes': ('collapse',)}),
        ('Timestamps', {'fields': ('created_at', 'updated_at'),
                        'classes': ('collapse',)}),
    )

    def get_queryset(self, request):
        return super().get_queryset(request).select_related(
            'job', 'source', 'story', 'artifact'
        )

    # --- Display helpers -------------------------------------------------
    @admin.display(description='URL', ordering='original_url')
    def short_url(self, obj):
        from django.utils.html import format_html

        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">{}</a>',
            obj.original_url,
            obj.original_url[:70],
        )

    @admin.display(description='Became')
    def produced_target(self, obj):
        """Which Story/Artifact this page turned into, if any."""
        if obj.story_id:
            return f'Story: {obj.story.title}'
        if obj.artifact_id:
            return f'Artifact: {obj.artifact.title}'
        return '-'

    @admin.display(description='Provenance')
    def provenance_link(self, obj):
        """Jump to the structured provenance rows for this item."""
        from django.urls import NoReverseMatch, reverse
        from django.utils.html import format_html

        refs = obj.references.count()
        if not refs:
            return 'None recorded'
        try:
            url = reverse('admin:heritage_crawl_sourcereference_changelist')
        except NoReverseMatch:
            return f'{refs} reference(s)'
        return format_html('<a href="{}">{} reference(s)</a>', url, refs)

    # --- Actions (§13) ---------------------------------------------------
    @admin.action(description='Approve selected (publish for readers)')
    def approve_items(self, request, queryset):
        approved, refusals = 0, []
        for item in queryset:
            try:
                approve_item(item, reviewer=request.user)
            except ReviewError as exc:
                refusals.append(str(exc))
                continue
            approved += 1
        if approved:
            self.message_user(
                request, f'Approved and published {approved} item(s).',
                messages.SUCCESS,
            )
        if refusals:
            self.message_user(
                request,
                'Could not approve '
                f'{len(refusals)} item(s). First problem: {refusals[0]}',
                messages.WARNING,
            )

    @admin.action(description='Reject selected')
    def reject_items(self, request, queryset):
        count = _bulk(queryset, 'reject', request.user)
        self.message_user(request, f'Rejected {count} item(s).', messages.SUCCESS)

    @admin.action(description='Request correction on selected')
    def request_correction_items(self, request, queryset):
        count = _bulk(queryset, 'request_correction', request.user)
        self.message_user(
            request, f'Flagged {count} item(s) as needing correction.',
            messages.WARNING,
        )

    @admin.action(description='Remove imported content (discards audit trail)')
    def remove_items(self, request, queryset):
        removed = 0
        for item in queryset:
            if item.story_id:
                item.story.delete()
            if item.artifact_id:
                item.artifact.delete()
            item.delete()
            removed += 1
        self.message_user(
            request,
            f'Removed {removed} item(s) and the content they produced. '
            'The crawl job counters still record that these pages were seen.',
            messages.SUCCESS,
        )


def _bulk(queryset, action: str, reviewer) -> int:
    """Apply a status action to many items; items in the wrong state are skipped."""
    handler = {'reject': reject, 'request_correction': request_correction}[action]
    return sum(1 for item in queryset if handler(item, reviewer=reviewer))


@admin.register(SourceReference)
class SourceReferenceAdmin(admin.ModelAdmin):
    list_display = (
        'source',
        'original_url',
        'institution',
        'author',
        'publication_date',
        'extraction_method',
        'licence',
        'confidence_score',
        'extracted_verbatim',
    )
    list_filter = ('source', 'extraction_method', 'extracted_verbatim')
    search_fields = ('original_url', 'institution', 'author')
    date_hierarchy = 'crawled_at'
    readonly_fields = ('source', 'original_url', 'crawled_at',
                       'extraction_method', 'confidence_score',
                       'extracted_verbatim', 'created_at')

    fieldsets = (
        ('Traceability (§5 — never edited)', {
            'fields': ('source', 'original_url', 'crawled_at',
                       'extraction_method', 'confidence_score',
                       'extracted_verbatim'),
            'description': 'original_url is read-only by design. §5: never '
                           'remove the original URL.',
        }),
        ('Attribution', {
            'fields': ('author', 'institution', 'publication_date',
                       'licence', 'attribution'),
        }),
        ('Linked item', {'fields': ('item',), 'classes': ('collapse',)}),
        ('Created', {'fields': ('created_at',), 'classes': ('collapse',)}),
    )

    def has_delete_permission(self, request, obj=None):
        # Deleting provenance destroys the ability to trace content to its
        # source. Deliberately not allowed here.
        return False


@admin.register(CrawlMedia)
class CrawlMediaAdmin(admin.ModelAdmin):
    list_display = (
        'media_type',
        'original_url',
        'local_path',
        'file_size',
        'checksum',
        'licence',
        'reused',
        'item',
    )
    list_filter = ('media_type', 'reused', 'licence')
    search_fields = ('original_url', 'local_path', 'checksum', 'attribution')
    readonly_fields = ('item', 'target', 'artifact', 'checksum', 'reused',
                       'created_at')

    fieldsets = (
        ('File', {
            'fields': ('media_type', 'original_url', 'local_path',
                       'mime_type', 'file_size', 'checksum'),
            'description': 'local_path is empty when the file was not '
                           'downloaded because reuse permission could not be '
                           'established (§6).',
        }),
        ('Rights', {'fields': ('licence', 'attribution', 'reused', 'alt_text')}),
        ('Links', {'fields': ('item', 'target', 'artifact'),
                   'classes': ('collapse',)}),
    )
