from django.apps import AppConfig


class GamificationConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'gamification'
    verbose_name = 'Gamification'

    def ready(self):
        # Registers the post_save receiver that provisions a quiz whenever a
        # story is published.
        from . import signals  # noqa: F401
