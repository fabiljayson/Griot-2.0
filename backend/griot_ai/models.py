"""Griot AI — the grounded question-answering layer.

`media_app` generates media (video, narration); this app answers questions. The
split matters because the two have different cost, latency and failure
semantics: a failed render is retried later, a failed answer is shown to a
reader standing in front of an artifact.

What is stored here is deliberately small: the conversation, each question, each
answer, which model produced it, and how long it took. No prompt text is
persisted beyond the question itself — the assembled context is reproducible
from the cited rows, and storing it again would mean copying artifact and story
text into a second table where it would quietly go stale.
"""

from django.conf import settings
from django.db import models
from django.utils.translation import gettext_lazy as _


class GriotConversation(models.Model):
    """One thread of questions, optionally grounded in one subject.

    A conversation is created per ask when the caller does not supply one, and
    reused when they do — which is what lets the VR panel keep a thread open
    across several artifacts inside one experience.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='griot_conversations',
    )

    # --- What this thread is grounded in, when anything ---
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='griot_conversations',
    )
    story = models.ForeignKey(
        'stories.Story',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='griot_conversations',
    )
    experience = models.ForeignKey(
        'vr.VRExperience',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='griot_conversations',
    )

    language = models.CharField(
        max_length=10,
        default='en',
        help_text='Language the answers should be written in.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at']
        indexes = [
            models.Index(fields=['user', '-updated_at']),
        ]

    def __str__(self):
        return f'Conversation {self.pk} ({self.user})'


class GriotMessage(models.Model):
    """A single question or answer."""

    class Role(models.TextChoices):
        USER = 'user', _('Reader')
        ASSISTANT = 'assistant', _('Griot')

    conversation = models.ForeignKey(
        GriotConversation,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    role = models.CharField(max_length=12, choices=Role.choices)
    text = models.TextField()

    # --- Provenance of an answer ---
    # A reader is entitled to know whether a machine wrote this and which one.
    # Storing it per message (rather than as a deployment-wide constant) keeps
    # the answer honest after the model is changed underneath it.
    provider = models.CharField(
        max_length=40,
        blank=True,
        default='',
        help_text='Answering engine: gemini, mock, or empty for reader messages.',
    )
    model_name = models.CharField(
        max_length=80,
        blank=True,
        default='',
        help_text='Model identifier that produced the answer.',
    )
    degraded = models.BooleanField(
        default=False,
        help_text='True when a development mock produced this, not a real model.',
    )
    latency_ms = models.PositiveIntegerField(default=0)
    error_code = models.CharField(
        max_length=40,
        blank=True,
        default='',
        help_text='Failure reason when no answer could be produced.',
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [
            models.Index(fields=['conversation', 'created_at']),
        ]

    def __str__(self):
        return f'{self.get_role_display()}: {self.text[:40]}'


# Module-level choice alias — see the note in stories/models.py.
GriotMessageRoleChoices = GriotMessage.Role
