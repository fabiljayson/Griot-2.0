from django.contrib import admin
from django.utils import timezone

from .models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
)


@admin.register(StoryCategory)
class StoryCategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'slug', 'icon', 'color', 'created_at')
    prepopulated_fields = {'slug': ('name',)}
    search_fields = ('name',)


@admin.register(Story)
class StoryAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'author',
        'status',
        'language',
        'region',
        'view_count',
        'like_count',
        'created_at',
    )
    list_filter = ('status', 'language', 'categories', 'created_at')
    search_fields = ('title', 'content', 'summary', 'tags')
    prepopulated_fields = {'slug': ('title',)}
    raw_id_fields = ('author',)
    filter_horizontal = ('categories', 'co_authors')
    readonly_fields = ('view_count', 'like_count', 'bookmark_count', 'created_at', 'updated_at')

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

    def publish_stories(self, request, queryset):
        updated = queryset.update(status=Story.Status.PUBLISHED, published_at=timezone.now())
        self.message_user(request, f'{updated} stories published.')
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
    list_display = ('story', 'user', 'reason', 'resolved', 'created_at')
    list_filter = ('reason', 'resolved')
    raw_id_fields = ('user', 'story')
    search_fields = ('story__title', 'user__username')


@admin.register(ReadingProgress)
class ReadingProgressAdmin(admin.ModelAdmin):
    list_display = ('user', 'story', 'progress_percent', 'completed', 'updated_at')
    raw_id_fields = ('user', 'story')
    list_filter = ('completed',)