from django.apps import AppConfig


class WebConfig(AppConfig):
    """Server-rendered web interface mirroring the Griot AI mobile app."""

    default_auto_field = 'django.db.models.BigAutoField'
    name = 'web'
