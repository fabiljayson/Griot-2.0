from django.apps import AppConfig


class MediaConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'media_app'
    verbose_name = 'Media & AI Generation'
    
    def ready(self):
        # Import signals if needed
        pass