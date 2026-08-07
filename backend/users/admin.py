from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    """Admin panel for the custom user model with role management."""

    list_display = ('username', 'email', 'role', 'is_staff', 'is_active')
    list_filter = ('role', 'is_staff', 'is_superuser', 'is_active')
    search_fields = ('username', 'email')

    fieldsets = UserAdmin.fieldsets + (
        (
            'African Teller role',
            {'fields': ('role', 'institution')},
        ),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        (
            'African Teller role',
            {
                'fields': ('role', 'institution'),
                'classes': ('wide',),
            },
        ),
    )
