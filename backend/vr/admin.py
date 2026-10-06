from django.contrib import admin

from .models import VRExperience, VRExperienceArtifact, VRLaunchToken, VRSession


class VRExperienceArtifactInline(admin.TabularInline):
    model = VRExperienceArtifact
    extra = 1
    autocomplete_fields = ('artifact',)
    fields = (
        'order',
        'artifact',
        'model_url',
        'model_scale',
        'is_interactive',
        'narration',
    )


@admin.register(VRExperience)
class VRExperienceAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'slug',
        'scene_identifier',
        'environment',
        'language',
        'is_active',
        'placement_count',
        'created_at',
    )
    list_filter = ('is_active', 'language', 'created_at')
    search_fields = ('title', 'description', 'scene_identifier', 'museum_name', 'region')
    prepopulated_fields = {'slug': ('title',)}
    inlines = (VRExperienceArtifactInline,)
    readonly_fields = ('created_at', 'updated_at')

    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'description', 'thumbnail', 'is_active'),
        }),
        ('Unity', {
            'fields': ('scene_identifier', 'environment'),
            'description': (
                'The scene name must exist in the shipped Unity build before '
                'the experience is activated — activating first launches readers '
                'into a scene that does not load.'
            ),
        }),
        ('Cultural Metadata', {
            'fields': ('language', 'museum_name', 'region', 'culture'),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    @admin.display(description='Artifacts')
    def placement_count(self, obj) -> int:
        return obj.placements.count()


@admin.register(VRLaunchToken)
class VRLaunchTokenAdmin(admin.ModelAdmin):
    """Visits only — a launch token has no editable state by design.

    The plaintext token does not exist here (only its digest), so there is
    nothing useful to show and nothing to correct: a bad token is reissued by
    tapping the button again.
    """

    list_display = ('id', 'user', 'experience', 'created_at', 'expires_at', 'used_at')
    list_filter = ('created_at',)
    search_fields = ('user__username', 'experience__title')
    raw_id_fields = ('user', 'experience', 'artifact')
    readonly_fields = (
        'user', 'experience', 'artifact', 'token_hash',
        'expires_at', 'used_at', 'created_at',
    )

    def has_add_permission(self, request):  # noqa: D102 - Django hook
        return False


@admin.register(VRSession)
class VRSessionAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'experience',
        'start_time',
        'duration_seconds',
        'completion_status',
        'progress',
        'xp_awarded',
    )
    list_filter = ('completion_status', 'experience', 'start_time')
    search_fields = ('user__username', 'experience__title', 'device_model')
    raw_id_fields = ('user', 'experience', 'launch_token')
    filter_horizontal = ('artifacts_viewed',)
    readonly_fields = ('start_time', 'created_at', 'updated_at', 'xp_awarded')
