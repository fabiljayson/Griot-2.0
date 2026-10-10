"""Serializers for the VR API.

Every response shape is declared explicitly rather than with `DictField` or
`ReadOnlyField`. `DictField` publishes an untyped blob, which drf-spectacular
accepts only at the cost of a schema no generated client can use — and the two
clients here (Flutter, Unity/C#) are both hand-written from this schema.
"""

from rest_framework import serializers

from .models import VRSession


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------
class VRSessionSerializer(serializers.ModelSerializer):
    artifacts_viewed = serializers.PrimaryKeyRelatedField(many=True, read_only=True)

    class Meta:
        model = VRSession
        fields = [
            'id',
            'user',
            'experience',
            'start_time',
            'end_time',
            'duration_seconds',
            'completion_status',
            'progress',
            'xp_awarded',
            'device_model',
            'artifacts_viewed',
        ]
        read_only_fields = fields


class VRProfileSerializer(serializers.Serializer):
    """The gamification numbers a completed session moved."""

    total_xp = serializers.IntegerField()
    level = serializers.IntegerField()


# ---------------------------------------------------------------------------
# Content payloads
# ---------------------------------------------------------------------------
class VRStoryRefSerializer(serializers.Serializer):
    """Just enough of a story for a client to fetch the whole thing."""

    id = serializers.IntegerField()
    slug = serializers.CharField()
    title = serializers.CharField()
    language = serializers.CharField()


class VRNarrationSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    audio_url = serializers.CharField()
    language = serializers.CharField()
    voice_id = serializers.CharField()
    duration = serializers.IntegerField()
    # A synthesised voice must not be mistakable for a community member
    # reciting their own tradition, in VR least of all — the headset is the one
    # surface where the reader has no page to check.
    is_synthetic = serializers.BooleanField()
    attribution = serializers.CharField()


class VRArtifactSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    slug = serializers.CharField()
    name = serializers.CharField()
    description = serializers.CharField()
    category = serializers.CharField()
    content_type = serializers.CharField()
    culture = serializers.CharField()
    region = serializers.CharField()
    estimated_date = serializers.CharField()
    materials = serializers.CharField()
    dimensions = serializers.CharField()
    image = serializers.CharField(allow_null=True)
    museum_name = serializers.CharField()
    floor = serializers.CharField()
    display_case = serializers.CharField()
    historical_significance = serializers.CharField(allow_blank=True)
    source_url = serializers.CharField(allow_blank=True)
    stories = VRStoryRefSerializer(many=True)


class VRPlacedArtifactSerializer(VRArtifactSerializer):
    """An artifact as placed in a scene — the artifact plus its position."""

    order = serializers.IntegerField()
    model_url = serializers.CharField(allow_null=True)
    model_scale = serializers.FloatField()
    is_interactive = serializers.BooleanField()
    narration = VRNarrationSerializer(allow_null=True)


class VRExperienceSummarySerializer(serializers.Serializer):
    id = serializers.IntegerField()
    slug = serializers.CharField()
    title = serializers.CharField()
    description = serializers.CharField()
    scene_identifier = serializers.CharField()
    thumbnail = serializers.CharField(allow_null=True)
    language = serializers.CharField()


class VRExperiencePayloadSerializer(VRExperienceSummarySerializer):
    """What Unity loads a scene from."""

    environment = serializers.CharField()
    museum_name = serializers.CharField()
    region = serializers.CharField()
    culture = serializers.CharField()
    updated_at = serializers.DateTimeField()
    artifact_count = serializers.IntegerField()
    artifacts = VRPlacedArtifactSerializer(many=True)


class VRArtifactDetailResponseSerializer(VRArtifactSerializer):
    """Artifact plus the active experiences it can be visited in."""

    experiences = VRExperienceSummarySerializer(many=True)


# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
class VRLaunchRequestSerializer(serializers.Serializer):
    """`POST /api/vr/launch/` body.

    Both an id and a slug are accepted for either field because the two clients
    speak different languages: the Flutter artifact page knows slugs, while a
    Unity build that already holds a payload works in ids.
    """

    experience = serializers.CharField(
        required=False,
        allow_blank=False,
        help_text='Experience id or slug. Optional when `artifact` identifies exactly one.',
    )
    artifact = serializers.CharField(
        required=False,
        allow_blank=False,
        help_text='Artifact id or slug the reader tapped.',
    )

    def validate(self, attrs):
        if not attrs.get('experience') and not attrs.get('artifact'):
            raise serializers.ValidationError(
                'Send an experience or an artifact to launch into.'
            )
        return attrs


class VRLaunchResponseSerializer(serializers.Serializer):
    token = serializers.CharField()
    expires_at = serializers.DateTimeField()
    expires_in = serializers.IntegerField()
    deep_link = serializers.CharField(
        help_text='griotvr:// URI to hand to Android. Valid once, briefly.',
    )
    experience = VRExperienceSummarySerializer()
    artifact = VRArtifactSerializer(allow_null=True)


class VRExchangeRequestSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=200)
    device_model = serializers.CharField(
        required=False, allow_blank=True, max_length=120,
    )


class VRExchangeResponseSerializer(serializers.Serializer):
    access_token = serializers.CharField(
        help_text='VR-scoped JWT: `scope=vr`, `sid` = session id. No refresh token.',
    )
    expires_in = serializers.IntegerField()
    session = VRSessionSerializer()
    experience = VRExperiencePayloadSerializer()


class VRSessionStartRequestSerializer(serializers.Serializer):
    experience = serializers.CharField(
        help_text='Experience id or slug to open a session for.',
    )


class VRSessionCompleteRequestSerializer(serializers.Serializer):
    completion_status = serializers.ChoiceField(
        choices=VRSession.Status.choices,
        default=VRSession.Status.COMPLETED,
    )
    progress = serializers.FloatField(min_value=0.0, max_value=1.0, required=False)
    duration_seconds = serializers.IntegerField(min_value=0, required=False)
    artifacts_viewed = serializers.ListField(
        child=serializers.IntegerField(),
        required=False,
        help_text='Artifact ids the reader actually opened; validated against the experience.',
    )


class VRSessionCompleteResponseSerializer(serializers.Serializer):
    session = VRSessionSerializer()
    xp_awarded = serializers.IntegerField(
        help_text='XP paid by *this* call. Zero when a retry finds it already paid.',
    )
    profile = VRProfileSerializer(allow_null=True)


# ---------------------------------------------------------------------------
# Progress
# ---------------------------------------------------------------------------
class VRProgressEntrySerializer(serializers.Serializer):
    """One experience's progress, rolled up across all of the reader's visits."""

    experience = VRExperienceSummarySerializer()
    session_count = serializers.IntegerField()
    completion_percentage = serializers.IntegerField(
        min_value=0,
        max_value=100,
        help_text='0–100. Always 100 once any session for it completed.',
    )
    completed = serializers.BooleanField()
    last_seen_at = serializers.DateTimeField()


class VRProgressRequestSerializer(serializers.Serializer):
    """`POST`/`PATCH /api/vr/progress/` body.

    The session is taken from the token's `sid` claim, not from the body: a
    headset cannot progress someone else's visit by naming its id.
    """

    progress = serializers.FloatField(
        min_value=0.0,
        max_value=1.0,
        required=False,
        help_text='Fraction of the experience completed, 0.0–1.0.',
    )
    artifacts_viewed = serializers.ListField(
        child=serializers.IntegerField(),
        required=False,
        help_text=(
            'The reader\'s complete viewed-artifact list so far (replaces, not '
            'appends); validated against the experience.'
        ),
    )

    def validate(self, attrs):
        if not attrs:
            raise serializers.ValidationError(
                'Send `progress` and/or `artifacts_viewed`.'
            )
        return attrs


# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
class VRLocationSerializer(serializers.Serializer):
    """A place experiences can be visited in, with what it holds."""

    museum_name = serializers.CharField()
    region = serializers.CharField()
    culture = serializers.CharField()
    experience_count = serializers.IntegerField()
    experiences = VRExperienceSummarySerializer(many=True)
