"""
Django Admin configuration for Artifact model.

Features:
- Pre-populated slug from title
- QR code thumbnail preview in list view
- Download/print-ready QR code button in detail view
- Bulk QR code generation action
"""

from django.contrib import admin
from django.utils.html import format_html

from .models import Artifact


@admin.register(Artifact)
class ArtifactAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'category',
        'location',
        'slug',
        'qr_code_thumbnail',
        'has_audio',
        'has_video',
        'created_at',
    )
    list_display_links = ('title', 'slug')
    prepopulated_fields = {'slug': ('title',)}
    readonly_fields = (
        'qr_code',
        'qr_code_preview',
        'created_at',
        'updated_at',
    )
    search_fields = ('title', 'story', 'location')
    list_filter = ('category', 'created_at')
    date_hierarchy = 'created_at'

    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'category', 'location'),
        }),
        ('Content', {
            'fields': ('story', 'historical_significance', 'source_url'),
        }),
        ('Media', {
            'fields': ('audio_file', 'video_url'),
        }),
        ('QR Code', {
            'fields': ('qr_code_preview', 'qr_code'),
            'description': 'QR code is auto-generated when the artifact is saved.',
        }),
        ('Metadata', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    actions = ['generate_qr_codes', 'download_qr_codes']

    def qr_code_thumbnail(self, obj):
        """Display a small thumbnail of the QR code in the list view."""
        if obj.qr_code:
            return format_html(
                '<img src="{}" width="80" height="80" '
                'style="border: 1px solid #ddd; border-radius: 4px;" '
                'alt="QR Code" />',
                obj.qr_code.url,
            )
        return format_html(
            '<span style="color: #999; font-style: italic;">No QR</span>'
        )
    qr_code_thumbnail.short_description = 'QR Code'

    def qr_code_preview(self, obj):
        """Display a larger preview of the QR code in the detail view."""
        if obj.qr_code:
            return format_html(
                '<div style="margin: 10px 0;">'
                '<img src="{}" width="200" height="200" '
                'style="border: 2px solid #333; border-radius: 8px; '
                'box-shadow: 0 2px 8px rgba(0,0,0,0.1);" '
                'alt="QR Code Preview" />'
                '<div style="margin-top: 10px;">'
                '<a href="{}" download="{}-qr.png" '
                'style="display: inline-block; padding: 8px 16px; '
                'background-color: #C85A32; color: white; '
                'text-decoration: none; border-radius: 4px; '
                'font-weight: bold;">'
                '⬇ Download Print-Ready QR</a>'
                '</div>'
                '<p style="margin-top: 8px; color: #666; font-size: 12px;">'
                'Right-click → "Save image as…" for high-resolution print.</p>'
                '</div>',
                obj.qr_code.url,
                obj.qr_code.url,
                obj.slug,
            )
        return format_html(
            '<p style="color: #999; font-style: italic;">'
            'Save the artifact to generate a QR code.</p>'
        )
    qr_code_preview.short_description = 'QR Code Preview'

    def has_audio(self, obj):
        """Show icon if audio file exists."""
        if obj.audio_file:
            return format_html('🎵')
        return format_html('<span style="color: #ccc;">—</span>')
    has_audio.short_description = 'Audio'

    def has_video(self, obj):
        """Show icon if video URL exists."""
        if obj.video_url:
            return format_html('🎬')
        return format_html('<span style="color: #ccc;">—</span>')
    has_video.short_description = 'Video'

    def generate_qr_codes(self, request, queryset):
        """Bulk action to regenerate QR codes for selected artifacts."""
        count = 0
        for artifact in queryset:
            artifact._generate_qr_code()
            count += 1
        self.message_user(request, f'✅ Generated QR codes for {count} artifact(s).')
    generate_qr_codes.short_description = '🔄 Generate QR codes for selected artifacts'

    def download_qr_codes(self, request, queryset):
        """Informational action about downloading QR codes."""
        count = queryset.filter(qr_code__isnull=False).count()
        self.message_user(
            request,
            f'💡 {count} artifact(s) have QR codes. '
            f'Open each artifact to download individual QR codes.',
        )
    download_qr_codes.short_description = '📥 Download QR codes (open each artifact)'

    def save_model(self, request, obj, form, change):
        """Override save to ensure QR code is generated."""
        super().save_model(request, obj, form, change)
