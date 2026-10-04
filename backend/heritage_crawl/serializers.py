"""
Serializers for the crawler administration API (§18).

Everything here is read-only except the review actions, which take a reason
string. That asymmetry is deliberate: §11 asks the crawler to insert data
"through a dedicated ingestion/service layer rather than directly manipulating
unrelated application logic", so these endpoints are a control panel for
`ingest` and `review`, not a second way to write heritage content. A reviewer
who wants to change a story's text edits the story.

Provenance is included on every item serializer rather than only on the detail
view. §5's guarantee is that an administrator can trace any imported item to its
source, and a list view that omitted the URL would be a list view that quietly
encourages approving things nobody checked.
"""

from rest_framework import serializers

from .models import CrawledItem, CrawlJob, CrawlMedia, CrawlSource, SourceReference


class CrawlSourceSerializer(serializers.ModelSerializer):
    """Configuration. Read-only over HTTP — sources are edited in the admin.

    Allowing source creation here would let an authenticated administrator point
    the crawler at an arbitrary host, which §20 specifically rules out
    ("Do not allow arbitrary external URLs to be fetched through an unrestricted
    API endpoint"). The domain allow-list is the SSRF boundary, so it stays
    behind the admin's audited login.
    """

    # `source` omitted deliberately: it would equal the field name, and DRF
    # asserts on that at bind time -- which broke `manage.py spectacular`
    # outright rather than warning.
    domain_allowlist = serializers.ListField(read_only=True)

    class Meta:
        model = CrawlSource
        fields = (
            'id',
            'slug',
            'name',
            'base_url',
            'source_type',
            'reliability',
            'enabled',
            'is_builtin',
            'max_pages',
            'max_depth',
            'request_delay',
            'timeout',
            'relevance_threshold',
            'allowed_domains',
            'domain_allowlist',
            'seed_urls',
            'default_licence',
            'allow_media_download',
        )
        read_only_fields = fields


class CrawlJobSerializer(serializers.ModelSerializer):
    """One run of the crawler, with the §16 summary attached."""

    source = serializers.CharField(source='source.name', read_only=True)
    source_slug = serializers.CharField(source='source.slug', read_only=True)
    duration_seconds = serializers.FloatField(read_only=True)
    summary = serializers.SerializerMethodField()
    triggered_by = serializers.CharField(
        source='triggered_by.username', read_only=True, default=None
    )

    class Meta:
        model = CrawlJob
        fields = (
            'id',
            'source',
            'source_slug',
            'status',
            'started_at',
            'completed_at',
            'duration_seconds',
            'summary',
            'triggered_by',
            'notes',
            'pages_processed',
            'pages_skipped',
            'items_found',
            'items_imported',
            'duplicates_found',
            'errors',
        )
        read_only_fields = fields

    def get_summary(self, obj) -> dict:
        return obj.summary()


class SourceReferenceSerializer(serializers.ModelSerializer):
    """Provenance for one source claim about an item."""

    source_name = serializers.CharField(source='source.name', read_only=True)
    source_slug = serializers.CharField(source='source.slug', read_only=True)

    class Meta:
        model = SourceReference
        fields = (
            'id',
            'source_name',
            'source_slug',
            'original_url',
            'author',
            'institution',
            'publication_date',
            'crawled_at',
            'extraction_method',
            'licence',
            'attribution',
            'confidence_score',
            # §21: lets a reviewer see at a glance whether the stored wording
            # is the source's or ours.
            'extracted_verbatim',
        )
        read_only_fields = fields


class CrawlMediaSerializer(serializers.ModelSerializer):
    class Meta:
        model = CrawlMedia
        fields = (
            'id',
            'media_type',
            'mime_type',
            'original_url',
            'local_path',
            'file_size',
            'checksum',
            'licence',
            'attribution',
            'alt_text',
            'reused',
        )
        read_only_fields = fields


class CrawledItemSerializer(serializers.ModelSerializer):
    """A discovered page and what became of it.

    `produced` is a single string naming the Story or Artifact rather than two
    nested serializers. A reviewer scanning the queue needs to know *what this
    page became*, and nesting the full story object would pull approval-adjacent
    fields into a read model and invite someone to edit through it.
    """

    source = serializers.CharField(source='source.name', read_only=True)
    source_slug = serializers.CharField(source='source.slug', read_only=True)
    job_id = serializers.IntegerField(read_only=True)
    produced = serializers.SerializerMethodField()
    references = SourceReferenceSerializer(many=True, read_only=True)
    media = CrawlMediaSerializer(many=True, read_only=True)

    class Meta:
        model = CrawledItem
        fields = (
            'id',
            'job_id',
            'source',
            'source_slug',
            'original_url',
            'extracted_title',
            'extracted_alt_title',
            'extracted_description',
            'extracted_content',
            'extracted_metadata',
            'relevance_score',
            'relevance_reasons',
            'processing_status',
            'error_type',
            'error_message',
            'produced',
            'references',
            'media',
            'created_at',
        )
        read_only_fields = fields

    def get_produced(self, obj) -> str | None:
        if obj.story_id:
            return f'story:{obj.story_id}'
        if obj.artifact_id:
            return f'artifact:{obj.artifact_id}'
        return None


class CrawlStartSerializer(serializers.Serializer):
    """Body for POST /api/crawler/start/.

    Accepts a source *slug*, never a URL. The reason is §20: an endpoint that
    takes a URL is an endpoint that can be pointed at an internal address. A
    slug only resolves to a `CrawlSource` whose domain allow-list was already
    set by an administrator, so the reachable set is bounded by configuration
    rather than by the caller.
    """

    source = serializers.CharField(
        help_text='Slug of an enabled CrawlSource. Not a URL, by design.'
    )
    max_pages = serializers.IntegerField(required=False, min_value=1, max_value=200)
    store_full_text = serializers.BooleanField(required=False)


class ReviewActionSerializer(serializers.Serializer):
    """Body for approve/reject/correct endpoints."""

    reason = serializers.CharField(
        required=False, allow_blank=True, max_length=1000,
        help_text='Recorded in the Story reviewer notes for reject/correct.',
    )
