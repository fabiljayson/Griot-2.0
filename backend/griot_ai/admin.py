from django.contrib import admin

from .models import GriotConversation, GriotMessage


class GriotMessageInline(admin.TabularInline):
    model = GriotMessage
    extra = 0
    can_delete = False
    fields = ('role', 'text', 'provider', 'model_name', 'degraded', 'latency_ms', 'error_code')
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):  # noqa: D102 - Django hook
        return False


@admin.register(GriotConversation)
class GriotConversationAdmin(admin.ModelAdmin):
    """Read-only history.

    Answers are a record of what a reader was told; editing one would destroy
    the only evidence of what the platform said. Nothing here is editable.
    """

    list_display = ('id', 'user', 'artifact', 'story', 'experience', 'language', 'updated_at')
    list_filter = ('language', 'created_at')
    search_fields = ('user__username', 'messages__text')
    raw_id_fields = ('user', 'artifact', 'story', 'experience')
    inlines = (GriotMessageInline,)
    date_hierarchy = 'created_at'

    def has_add_permission(self, request):  # noqa: D102 - Django hook
        return False

    def has_change_permission(self, request, obj=None):  # noqa: D102 - Django hook
        return False


@admin.register(GriotMessage)
class GriotMessageAdmin(admin.ModelAdmin):
    list_display = ('id', 'conversation', 'role', 'provider', 'model_name', 'degraded', 'created_at')
    list_filter = ('role', 'provider', 'degraded')
    search_fields = ('text',)
    raw_id_fields = ('conversation',)
    readonly_fields = (
        'conversation', 'role', 'text', 'provider', 'model_name',
        'degraded', 'latency_ms', 'error_code', 'created_at',
    )
