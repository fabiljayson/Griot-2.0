from django.contrib import admin

from .models import Artifact, QRCodeScan


@admin.register(Artifact)
class ArtifactAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'category',
        'culture',
        'region',
        'museum_name',
        'is_published',
        'created_by',
        'created_at',
    )
    list_filter = ('category', 'is_published', 'culture', 'created_at')
    search_fields = ('title', 'description', 'culture', 'region', 'museum_name')
    prepopulated_fields = {'slug': ('title',)}
    raw_id_fields = ('created_by',)
    filter_horizontal = ('stories',)
    readonly_fields = (
        'slug',
        'qr_code_url',
        'qr_code_svg',
        'deep_link_path',
        'created_at',
        'updated_at',
    )

    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'description', 'category', 'is_published'),
        }),
        ('Cultural Metadata', {
            'fields': ('culture', 'region', 'estimated_date', 'materials', 'dimensions'),
        }),
        ('Media', {
            'fields': ('image', 'image_blurhash', 'additional_images'),
        }),
        ('QR Code', {
            'fields': ('qr_code_url', 'qr_code_svg', 'deep_link_path'),
            'classes': ('collapse',),
        }),
        ('Related Stories', {
            'fields': ('stories',),
        }),
        ('Location', {
            'fields': ('museum_name', 'floor', 'display_case'),
        }),
        ('Ownership', {
            'fields': ('created_by',),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    actions = ['publish_artifacts', 'unpublish_artifacts', 'generate_qr_codes']

    def publish_artifacts(self, request, queryset):
        updated = queryset.update(is_published=True)
        self.message_user(request, f'{updated} artifacts published.')
    publish_artifacts.short_description = 'Publish selected artifacts'

    def unpublish_artifacts(self, request, queryset):
        updated = queryset.update(is_published=False)
        self.message_user(request, f'{updated} artifacts unpublished.')
    unpublish_artifacts.short_description = 'Unpublish selected artifacts'

    def generate_qr_codes(self, request, queryset):
        from .services.qr_generator import get_qr_generator
        qr_gen = get_qr_generator()
        count = 0
        for artifact in queryset:
            result = qr_gen.generate_for_artifact(artifact)
            artifact.qr_code_svg = result['svg']
            artifact.save(update_fields=['qr_code_svg'])
            count += 1
        self.message_user(request, f'{count} QR codes generated.')
    generate_qr_codes.short_description = 'Generate QR codes for selected artifacts'


@admin.register(QRCodeScan)
class QRCodeScanAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'artifact',
        'user',
        'device_type',
        'created_at',
    )
    list_filter = ('device_type', 'created_at')
    search_fields = ('artifact__title', 'user__username')
    raw_id_fields = ('artifact', 'user')
    readonly_fields = (
        'artifact',
        'user',
        'device_type',
        'ip_address',
        'user_agent',
        'latitude',
        'longitude',
        'created_at',
    )
