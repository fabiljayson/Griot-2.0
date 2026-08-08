from rest_framework import serializers

from .models import Artifact, QRCodeScan


class ArtifactListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for artifact list views."""

    created_by_username = serializers.CharField(
        source='created_by.username',
        read_only=True,
        default='',
    )
    story_count = serializers.SerializerMethodField()
    scan_count = serializers.SerializerMethodField()

    class Meta:
        model = Artifact
        fields = [
            'id',
            'title',
            'slug',
            'category',
            'culture',
            'region',
            'estimated_date',
            'image',
            'image_blurhash',
            'museum_name',
            'is_published',
            'created_by_username',
            'story_count',
            'scan_count',
            'created_at',
        ]

    def get_story_count(self, obj):
        return obj.stories.count()

    def get_scan_count(self, obj):
        return obj.scans.count()


class ArtifactDetailSerializer(serializers.ModelSerializer):
    """Full serializer for artifact detail views."""

    created_by_username = serializers.CharField(
        source='created_by.username',
        read_only=True,
        default='',
    )
    stories = serializers.SerializerMethodField()
    scan_count = serializers.SerializerMethodField()
    qr_deep_link = serializers.ReadOnlyField()

    class Meta:
        model = Artifact
        fields = [
            'id',
            'title',
            'slug',
            'description',
            'category',
            'created_by',
            'created_by_username',
            'culture',
            'region',
            'estimated_date',
            'materials',
            'dimensions',
            'image',
            'image_blurhash',
            'additional_images',
            'qr_code_url',
            'qr_code_svg',
            'deep_link_path',
            'qr_deep_link',
            'stories',
            'museum_name',
            'floor',
            'display_case',
            'is_published',
            'created_at',
            'updated_at',
            'scan_count',
        ]
        read_only_fields = [
            'id',
            'slug',
            'qr_code_url',
            'qr_code_svg',
            'deep_link_path',
            'qr_deep_link',
            'created_at',
            'updated_at',
        ]

    def get_stories(self, obj):
        from stories.serializers import StoryListSerializer
        return StoryListSerializer(obj.stories.all(), many=True).data

    def get_scan_count(self, obj):
        return obj.scans.count()


class ArtifactCreateUpdateSerializer(serializers.ModelSerializer):
    """Serializer for creating/updating artifacts."""

    story_ids = serializers.ListField(
        child=serializers.IntegerField(),
        required=False,
        write_only=True,
        help_text='List of story IDs to link to this artifact.',
    )

    class Meta:
        model = Artifact
        fields = [
            'title',
            'description',
            'category',
            'culture',
            'region',
            'estimated_date',
            'materials',
            'dimensions',
            'image',
            'additional_images',
            'museum_name',
            'floor',
            'display_case',
            'is_published',
            'story_ids',
        ]
        read_only_fields = ['slug', 'deep_link_path']

    def create(self, validated_data):
        story_ids = validated_data.pop('story_ids', [])
        artifact = Artifact.objects.create(**validated_data)
        if story_ids:
            artifact.stories.set(story_ids)
        return artifact

    def update(self, instance, validated_data):
        story_ids = validated_data.pop('story_ids', None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        if story_ids is not None:
            instance.stories.set(story_ids)
        return instance


class QRCodeGenerateSerializer(serializers.Serializer):
    """Serializer for QR code generation requests."""

    foreground = serializers.CharField(
        max_length=7,
        default='#C85A32',
        help_text='Foreground color (hex).',
    )
    background = serializers.CharField(
        max_length=7,
        default='#FFFFFF',
        help_text='Background color (hex).',
    )
    format = serializers.ChoiceField(
        choices=['svg', 'png', 'data_uri'],
        default='svg',
    )


class QRCodeScanSerializer(serializers.ModelSerializer):
    """Serializer for QR code scan records."""

    artifact_title = serializers.CharField(
        source='artifact.title',
        read_only=True,
    )

    class Meta:
        model = QRCodeScan
        fields = [
            'id',
            'artifact',
            'artifact_title',
            'user',
            'device_type',
            'latitude',
            'longitude',
            'created_at',
        ]
        read_only_fields = ['id', 'user', 'created_at']
