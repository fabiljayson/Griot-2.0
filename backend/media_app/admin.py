from django.contrib import admin

from .models import AudioNarrationJob, VideoGenerationJob


@admin.register(VideoGenerationJob)
class VideoGenerationJobAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'story',
        'user',
        'status',
        'luma_job_id',
        'created_at',
    )
    list_filter = ('status', 'origin_kind', 'created_at')
    search_fields = ('story__title', 'user__username', 'luma_job_id')
    raw_id_fields = ('user', 'story')
    readonly_fields = (
        'luma_job_id',
        'status',
        'progress_percent',
        'video_url',
        'thumbnail_url',
        'duration',
        'error_message',
        'attribution',
        'created_at',
        'updated_at',
        'started_at',
        'completed_at',
    )
    
    fieldsets = (
        (None, {
            'fields': ('user', 'story', 'prompt'),
        }),
        ('Luma AI Details', {
            'fields': ('luma_job_id', 'luma_request_id'),
        }),
        ('Status', {
            'fields': ('status', 'progress_percent', 'error_message'),
        }),
        ('Output', {
            'fields': ('video_url', 'thumbnail_url', 'duration'),
        }),
        # Switch origin_kind to `human_recording` when a real camera footage
        # row replaces the AI render; `engine` then names nothing, so clear it.
        ('Provenance', {
            'fields': ('origin_kind', 'engine', 'attribution'),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at', 'started_at', 'completed_at'),
            'classes': ('collapse',),
        }),
    )


@admin.register(AudioNarrationJob)
class AudioNarrationJobAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'story',
        'user',
        'language',
        'voice_id',
        'status',
        'created_at',
    )
    list_filter = ('status', 'origin_kind', 'language', 'created_at')
    search_fields = ('story__title', 'user__username', 'voice_id')
    raw_id_fields = ('user', 'story')
    readonly_fields = (
        'status',
        'audio_url',
        'duration',
        'file_size',
        'error_message',
        'attribution',
        'created_at',
        'updated_at',
        'completed_at',
    )

    fieldsets = (
        (None, {
            'fields': ('user', 'story', 'narration_text'),
        }),
        ('Voice', {
            'fields': ('voice_id', 'language', 'speed'),
        }),
        ('Status', {
            'fields': ('status', 'duration', 'file_size', 'audio_url', 'error_message'),
        }),
        # `reviewed_by_source` is the only thing that makes this more than a
        # machine speaking someone else's words, so it is recorded next to the
        # engine that actually produced the audio rather than in a notes field.
        ('Provenance', {
            'fields': ('origin_kind', 'engine', 'reviewed_by_source', 'attribution'),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at', 'completed_at'),
            'classes': ('collapse',),
        }),
    )