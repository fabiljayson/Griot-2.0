from django.contrib import admin
from django.utils import timezone

from .models import (
    ModerationLog,
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
    StorySource,
    StoryVerification,
)
from .trust import trust_level


@admin.register(StoryCategory)
class StoryCategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'slug', 'icon', 'color', 'created_at')
    prepopulated_fields = {'slug': ('name',)}
    search_fields = ('name',)


class StorySourceInline(admin.TabularInline):
    """The itemised provenance — every source a reviewer can check."""

    model = StorySource
    extra = 1
    fields = (
        'source_type', 'name', 'author', 'institution', 'url',
        'reference', 'is_verified', 'verified_by', 'verified_at',
    )
    readonly_fields = ('verified_by', 'verified_at')


class StoryVerificationInline(admin.StackedInline):
    """The evidence checklist behind the Cultural Trust Score.

    The five boxes are the review; `trust_score` is read-only because it is
    their weighted sum, recomputed on save. `score_breakdown` (read-only
    below) shows the reviewer exactly which boxes are paying for which
    points.
    """

    model = StoryVerification
    fields = (
        'source_verified', 'community_validated', 'expert_validated',
        'references_confirmed', 'consistency_confirmed',
        'trust_score', 'reviewer', 'verified_at', 'notes',
    )
    readonly_fields = ('trust_score', 'reviewer', 'verified_at')
    can_delete = False


class ModerationLogInline(admin.TabularInline):
    """Append-only audit trail. No add form, no editable rows."""

    model = ModerationLog
    extra = 0
    fields = ('created_at', 'actor', 'action', 'from_status', 'to_status', 'notes')
    readonly_fields = fields
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Story)
class StoryAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'author',
        'status',
        'trust',
        'language',
        'region',
        'view_count',
        'like_count',
        'created_at',
    )
    list_filter = ('status', 'origin', 'consent_status', 'licence', 'language', 'categories', 'created_at')
    search_fields = ('title', 'content', 'summary', 'tags', 'provenance_notes', 'rights_holder')
    prepopulated_fields = {'slug': ('title',)}
    raw_id_fields = ('author',)
    filter_horizontal = ('categories', 'co_authors')
    inlines = [StorySourceInline, StoryVerificationInline, ModerationLogInline]
    readonly_fields = (
        'view_count',
        'like_count',
        'bookmark_count',
        'attribution',
        'created_at',
        'updated_at',
    )

    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'author', 'status'),
        }),
        ('Content', {
            'fields': ('content', 'summary'),
        }),
        ('Classification', {
            'fields': ('categories', 'language', 'region', 'tags'),
        }),
        ('Media', {
            'fields': ('cover_image', 'cover_image_blurhash', 'audio_url', 'video_url'),
        }),
        ('Metadata', {
            'fields': ('cultural_context', 'moral_lesson', 'source', 'estimated_read_time'),
        }),
        # Where this text came from and whether the community behind it agreed
        # to its publication. `attribution` is derived and shown read-only so a
        # reviewer can see the credit line the public will read.
        ('Provenance & rights', {
            'fields': (
                'origin',
                'provenance_notes',
                'recorded_at',
                'consent_status',
                'rights_holder',
                'licence',
                'attribution',
            ),
        }),
        ('Collaboration', {
            'fields': ('co_authors',),
            'classes': ('collapse',),
        }),
        ('Stats', {
            'fields': ('view_count', 'like_count', 'bookmark_count'),
        }),
        ('Moderation', {
            'fields': ('reviewer_notes', 'published_at'),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    actions = ['publish_stories', 'archive_stories']

    @admin.display(description='Trust')
    def trust(self, obj):
        """"92% · Verified" in the changelist — evidence strength, not truth."""
        verification = getattr(obj, 'verification', None)
        score = verification.trust_score if verification else 0
        return f'{score}% · {trust_level(score).title()}'

    def publish_stories(self, request, queryset):
        # Per-row save(), never queryset.update(): the model refuses to publish
        # a story whose community withheld consent, and a bulk UPDATE would step
        # straight past that guard.
        published = 0
        blocked = 0
        for story in queryset:
            if story.consent_status == Story.Consent.WITHHELD:
                blocked += 1
                continue
            story.status = Story.Status.PUBLISHED
            story.published_at = timezone.now()
            story.save()
            published += 1
        self.message_user(
            request,
            f'{published} stories published.'
            + (f' {blocked} skipped: consent is withheld.' if blocked else ''),
        )
    publish_stories.short_description = 'Publish selected stories'

    def archive_stories(self, request, queryset):
        updated = queryset.update(status=Story.Status.ARCHIVED)
        self.message_user(request, f'{updated} stories archived.')
    archive_stories.short_description = 'Archive selected stories'


@admin.register(StoryBookmark)
class StoryBookmarkAdmin(admin.ModelAdmin):
    list_display = ('user', 'story', 'created_at')
    raw_id_fields = ('user', 'story')
    search_fields = ('user__username', 'story__title')


@admin.register(StoryLike)
class StoryLikeAdmin(admin.ModelAdmin):
    list_display = ('user', 'story', 'created_at')
    raw_id_fields = ('user', 'story')


@admin.register(StoryFlag)
class StoryFlagAdmin(admin.ModelAdmin):
    list_display = ('story', 'user', 'reason', 'resolved', 'resolution_action', 'resolved_by', 'created_at')
    list_filter = ('reason', 'resolved', 'resolution_action')
    raw_id_fields = ('user', 'story', 'resolved_by')
    search_fields = ('story__title', 'user__username')
    readonly_fields = ('resolved_by', 'resolved_at')


@admin.register(StorySource)
class StorySourceAdmin(admin.ModelAdmin):
    list_display = ('name', 'story', 'source_type', 'is_verified', 'verified_by', 'created_at')
    list_filter = ('source_type', 'is_verified')
    search_fields = ('name', 'institution', 'story__title')
    raw_id_fields = ('story', 'verified_by')
    readonly_fields = ('verified_by', 'verified_at', 'created_at', 'updated_at')


@admin.register(StoryVerification)
class StoryVerificationAdmin(admin.ModelAdmin):
    """Evidence checklist with its breakdown spelled out."""

    list_display = ('story', 'trust_score', 'trust_level_display', 'reviewer', 'verified_at')
    list_filter = ('source_verified', 'community_validated', 'expert_validated')
    raw_id_fields = ('story', 'reviewer')
    readonly_fields = ('trust_score', 'created_at', 'updated_at')

    @admin.display(description='Level')
    def trust_level_display(self, obj):
        return trust_level(obj.trust_score).title()


@admin.register(ModerationLog)
class ModerationLogAdmin(admin.ModelAdmin):
    """Read-only audit trail: the log exists to be read, never edited."""

    list_display = ('created_at', 'story', 'actor', 'action', 'from_status', 'to_status')
    list_filter = ('action',)
    search_fields = ('story__title', 'actor__username', 'notes')
    raw_id_fields = ('story', 'actor')
    readonly_fields = (
        'story', 'actor', 'action', 'from_status', 'to_status', 'notes', 'created_at',
    )

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(ReadingProgress)
class ReadingProgressAdmin(admin.ModelAdmin):
    list_display = ('user', 'story', 'progress_percent', 'completed', 'updated_at')
    raw_id_fields = ('user', 'story')
    list_filter = ('completed',)