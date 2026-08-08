from rest_framework import serializers

from .models import AudioNarrationJob, VideoGenerationJob


class VideoGenerationJobSerializer(serializers.ModelSerializer):
    """Serializer for video generation jobs."""
    
    story_title = serializers.CharField(source='story.title', read_only=True)
    user_username = serializers.CharField(source='user.username', read_only=True)
    
    class Meta:
        model = VideoGenerationJob
        fields = [
            'id',
            'user',
            'user_username',
            'story',
            'story_title',
            'luma_job_id',
            'prompt',
            'status',
            'progress_percent',
            'video_url',
            'thumbnail_url',
            'duration',
            'error_message',
            'created_at',
            'updated_at',
            'started_at',
            'completed_at',
        ]
        read_only_fields = [
            'id',
            'user',
            'luma_job_id',
            'status',
            'progress_percent',
            'video_url',
            'thumbnail_url',
            'duration',
            'error_message',
            'created_at',
            'updated_at',
            'started_at',
            'completed_at',
        ]


class VideoGenerationCreateSerializer(serializers.Serializer):
    """Serializer for creating video generation jobs."""
    
    story_id = serializers.IntegerField()
    prompt = serializers.CharField(max_length=2000)
    duration = serializers.IntegerField(min_value=5, max_value=30, default=10)
    aspect_ratio = serializers.ChoiceField(
        choices=['16:9', '9:16', '1:1'],
        default='16:9',
    )


class AudioNarrationJobSerializer(serializers.ModelSerializer):
    """Serializer for audio narration jobs."""

    story_title = serializers.SerializerMethodField()
    artifact_id = serializers.IntegerField(source='artifact.id', read_only=True, default=None)
    artifact_title = serializers.SerializerMethodField()
    user_username = serializers.CharField(source='user.username', read_only=True)
    audio_url = serializers.SerializerMethodField()

    class Meta:
        model = AudioNarrationJob
        fields = [
            'id',
            'user',
            'user_username',
            'story',
            'story_title',
            'artifact_id',
            'artifact_title',
            'narration_text',
            'voice_id',
            'language',
            'speed',
            'status',
            'audio_url',
            'duration',
            'file_size',
            'error_message',
            'created_at',
            'updated_at',
            'completed_at',
        ]
        read_only_fields = [
            'id',
            'user',
            'story',
            'artifact_id',
            'artifact_title',
            'narration_text',
            'voice_id',
            'language',
            'speed',
            'status',
            'audio_url',
            'duration',
            'file_size',
            'error_message',
            'created_at',
            'updated_at',
            'completed_at',
        ]

    def get_story_title(self, obj):
        """Title used for playback: the story, or the artifact for audio guides."""
        if obj.story_id:
            return obj.story.title
        if obj.artifact_id:
            return obj.artifact.title
        return ''

    def get_artifact_title(self, obj):
        if obj.artifact_id:
            return obj.artifact.title
        return ''

    def get_audio_url(self, obj):
        """Serve the stored audio file as an absolute URL when available."""
        if obj.audio_file:
            request = self.context.get('request')
            url = obj.audio_file.url
            if request is not None:
                return request.build_absolute_uri(url)
            return url
        return obj.audio_url


class AudioNarrationCreateSerializer(serializers.Serializer):
    """Serializer for creating audio narration jobs."""

    story_id = serializers.IntegerField(required=False)
    artifact_id = serializers.IntegerField(required=False)
    voice_id = serializers.CharField(max_length=100, required=False)
    language = serializers.CharField(max_length=10, default='en')
    speed = serializers.FloatField(min_value=0.5, max_value=2.0, default=1.0)

    def validate(self, attrs):
        if not attrs.get('story_id') and not attrs.get('artifact_id'):
            raise serializers.ValidationError(
                'Either story_id or artifact_id is required.'
            )
        return attrs


class VoiceSerializer(serializers.Serializer):
    """Serializer for available voices."""
    
    id = serializers.CharField()
    name = serializers.CharField()
    gender = serializers.CharField()
    language = serializers.CharField()