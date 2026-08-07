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
    list_filter = ('status', 'created_at')
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
    list_filter = ('status', 'language', 'created_at')
    search_fields = ('story__title', 'user__username', 'voice_id')
    raw_id_fields = ('user', 'story')
    readonly_fields = (
        'status',
        'audio_url',
        'duration',
        'file_size',
        'error_message',
        'created_at',
        'updated_at',
        'completed_at',
    )