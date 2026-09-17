"""
Per-user web-only preferences (language toggle on the web home screen).

Mobile stores these in-app; the web UI persists them server-side so the
experience matches across browsers. Story/auth data itself is shared.
"""

from django.conf import settings
from django.db import models


class WebUserSettings(models.Model):
    """Web-interface preferences for a user (language, theme)."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='web_settings',
    )
    language = models.CharField(
        max_length=10,
        choices=[('en', 'English'), ('fr', 'French')],
        default='en',
    )
    # 'light' | 'dark' | 'system' — matches the mobile settings provider.
    theme = models.CharField(
        max_length=10,
        default='system',
        choices=[('light', 'Light'), ('dark', 'Dark'), ('system', 'System')],
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'Web settings for {self.user.username}'
