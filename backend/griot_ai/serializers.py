"""Serializers for the Griot AI endpoints."""

from rest_framework import serializers

from stories.models import Story

from .models import GriotConversation, GriotMessage


class GriotSourceSerializer(serializers.Serializer):
    """A record the answer was grounded in, so a reader can go and read it."""

    type = serializers.ChoiceField(choices=['artifact', 'story', 'experience'])
    id = serializers.IntegerField()
    slug = serializers.CharField()
    title = serializers.CharField()
    url = serializers.CharField(
        help_text='App path for the source, or empty when it has no page.',
    )


class GriotMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = GriotMessage
        fields = [
            'id',
            'role',
            'text',
            'provider',
            'model_name',
            'degraded',
            'latency_ms',
            'created_at',
        ]
        read_only_fields = fields


class GriotConversationSerializer(serializers.ModelSerializer):
    messages = GriotMessageSerializer(many=True, read_only=True)

    class Meta:
        model = GriotConversation
        fields = [
            'id',
            'artifact',
            'story',
            'experience',
            'language',
            'messages',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields


class GriotAskRequestSerializer(serializers.Serializer):
    """`POST /api/ai/ask/` body.

    `artifact`, `story` and `experience` are what the answer is grounded in and
    are all optional: a reader may also ask a general question, in which case the
    answer comes back with an empty `sources` list.
    """

    question = serializers.CharField(
        max_length=500,
        help_text='The reader’s question, in their own words.',
    )
    artifact = serializers.CharField(
        required=False, allow_blank=True,
        help_text='Artifact id or slug to ground the answer in.',
    )
    story = serializers.CharField(
        required=False, allow_blank=True,
        help_text='Story id or slug to ground the answer in.',
    )
    experience = serializers.CharField(
        required=False, allow_blank=True,
        help_text='VR experience id or slug to ground the answer in.',
    )
    conversation = serializers.IntegerField(
        required=False,
        help_text='Continue an existing conversation. Omit to start a new one.',
    )
    language = serializers.ChoiceField(
        choices=Story.Language.choices,
        required=False,
        help_text='Language to answer in. Defaults to the subject’s language.',
    )


class GriotAskResponseSerializer(serializers.Serializer):
    conversation_id = serializers.IntegerField()
    answer = serializers.CharField()
    provider = serializers.CharField()
    model_name = serializers.CharField()
    degraded = serializers.BooleanField(
        help_text='True when a development mock produced this answer, not a model.',
    )
    latency_ms = serializers.IntegerField()
    sources = GriotSourceSerializer(many=True)
