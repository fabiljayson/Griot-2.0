from django.contrib import admin

from .models import WebUserSettings


@admin.register(WebUserSettings)
class WebUserSettingsAdmin(admin.ModelAdmin):
    list_display = ('user', 'language', 'theme', 'updated_at')
    list_filter = ('language', 'theme')
    search_fields = ('user__username', 'user__email')
