"""Keep quizzes in step with the story catalogue.

A reader reaches a quiz through the story they are reading, so a published
story with no quiz is a dead "Take Quiz" button. Provisioning on publish means
the gap cannot reopen when a story goes live.
"""

from django.db.models.signals import post_save
from django.dispatch import receiver

from stories.models import Story


@receiver(post_save, sender=Story)
def provision_quiz_for_published_story(sender, instance, created, **kwargs):
    """Create or repair the quiz whenever a story is published.

    Only touches published stories, and only writes when the quiz is missing or
    empty, so a plain ``save()`` on an existing story stays cheap.
    """
    if instance.status != Story.Status.PUBLISHED:
        return

    # Imported here because gamification.models imports nothing from stories,
    # but the provisioner is only needed once a story actually goes live.
    from gamification.services.quiz_provisioner import ensure_quiz_for_story

    ensure_quiz_for_story(instance)
