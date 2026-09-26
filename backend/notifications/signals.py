from django.db import transaction
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from stories.models import Story

from . import services


@receiver(pre_save, sender=Story, dispatch_uid='notifications_remember_story_status')
def remember_previous_status(sender, instance, **kwargs):
    """Stash the status a story had before this save.

    Needed because ``post_save`` only sees the new value: without the previous
    one there is no way to tell publishing a story from re-saving one that is
    already live, and every save would re-announce it.
    """
    if not instance.pk:
        instance._previous_status = None
        return
    instance._previous_status = (
        Story.objects.filter(pk=instance.pk)
        .values_list('status', flat=True)
        .first()
    )


@receiver(post_save, sender=Story, dispatch_uid='notifications_on_story_publish')
def notify_readers_on_publish(sender, instance, created, raw=False, **kwargs):
    """Tell readers when a story *becomes* published.

    Only the draft/pending/rejected/archived -> published transition announces
    anything. Saving an already-live story — a typo fix, a content edit — must
    not put a second copy in every reader's inbox, and a view count bump does
    not even reach here because it is written with ``QuerySet.update()``, which
    bypasses signals.

    The send is deferred to ``on_commit`` so a publish that rolls back announces
    nothing, and the story's own transaction is not held open for one insert per
    reader.

    Skipped while loading fixtures (``raw``): a fixture load is not a publication
    event, and messages addressed to fixture users would outlive the test run.
    """
    if raw or instance.status != Story.Status.PUBLISHED:
        return
    if getattr(instance, '_previous_status', None) == Story.Status.PUBLISHED:
        return

    transaction.on_commit(lambda: services.notify_new_story(instance))
