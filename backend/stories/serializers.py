from django.contrib.auth import get_user_model
from rest_framework import serializers

from users.serializers import UserSerializer

from .models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
)

User = get_user_model()


class StoryCategorySerializer(serializers.ModelSerializer):
    """Serializer for story categories."""

    story_count = serializers.SerializerMethodField()

    class Meta:
        model = StoryCategory
        fields = ('id', 'name', 'slug', 'description', 'icon', 'color', 'story_count')

    def get_story_count(self, obj):
        return obj.stories.filter(status=Story.Status.PUBLISHED).count()


class StoryListSerializer(serializers.ModelSerializer):
    """Compact serializer for story listings and discovery."""

    author = UserSerializer(read_only=True)
    categories = StoryCategorySerializer(many=True, read_only=True)
    is_bookmarked = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()

    class Meta:
        model = Story
        fields = (
            'id',
            'title',
            'slug',
            'summary',
            'author',
            'categories',
            'language',
            'region',
            'cover_image',
            'cover_image_blurhash',
            'estimated_read_time',
            'view_count',
            'like_count',
            'bookmark_count',
            'is_bookmarked',
            'is_liked',
            'created_at',
            'published_at',
        )

    def get_is_bookmarked(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryBookmark.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_is_liked(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryLike.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False


class StoryDetailSerializer(serializers.ModelSerializer):
    """Full serializer for story detail view."""

    author = UserSerializer(read_only=True)
    categories = StoryCategorySerializer(many=True, read_only=True)
    category_ids = serializers.PrimaryKeyRelatedField(
        many=True,
        queryset=StoryCategory.objects.all(),
        source='categories',
        write_only=True,
        required=False,
    )
    is_bookmarked = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    reading_progress = serializers.SerializerMethodField()
    tag_list = serializers.ReadOnlyField()

    class Meta:
        model = Story
        fields = (
            'id',
            'title',
            'slug',
            'content',
            'summary',
            'author',
            'categories',
            'category_ids',
            'language',
            'region',
            'tags',
            'tag_list',
            'cover_image',
            'cover_image_blurhash',
            'audio_url',
            'video_url',
            'cultural_context',
            'moral_lesson',
            'source',
            'estimated_read_time',
            'status',
            'view_count',
            'like_count',
            'bookmark_count',
            'is_bookmarked',
            'is_liked',
            'reading_progress',
            'created_at',
            'updated_at',
            'published_at',
        )
        read_only_fields = (
            'id',
            'slug',
            'author',
            'cover_image_blurhash',
            'estimated_read_time',
            'view_count',
            'like_count',
            'bookmark_count',
            'created_at',
            'updated_at',
            'published_at',
        )

    def get_is_bookmarked(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryBookmark.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_is_liked(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryLike.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_reading_progress(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            progress = ReadingProgress.objects.filter(
                user=request.user, story=obj
            ).first()
            if progress:
                return {
                    'percent': progress.progress_percent,
                    'last_position': progress.last_read_position,
                    'completed': progress.completed,
                }
        return None


class StoryCreateUpdateSerializer(serializers.ModelSerializer):
    """Serializer for creating and updating stories."""

    category_ids = serializers.PrimaryKeyRelatedField(
        many=True,
        queryset=StoryCategory.objects.all(),
        source='categories',
        required=False,
    )

    class Meta:
        model = Story
        fields = (
            'title',
            'content',
            'summary',
            'categories',
            'category_ids',
            'language',
            'region',
            'tags',
            'cover_image',
            'audio_url',
            'video_url',
            'cultural_context',
            'moral_lesson',
            'source',
            'status',
        )
        read_only_fields = ('status',)

    def create(self, validated_data):
        categories = validated_data.pop('categories', [])
        story = Story.objects.create(**validated_data)
        if categories:
            story.categories.set(categories)
        return story

    def update(self, instance, validated_data):
        categories = validated_data.pop('categories', None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        if categories is not None:
            instance.categories.set(categories)
        return instance


class StoryBookmarkSerializer(serializers.ModelSerializer):
    """Serializer for story bookmarks."""

    story = StoryListSerializer(read_only=True)
    story_id = serializers.PrimaryKeyRelatedField(
        queryset=Story.objects.all(),
        source='story',
        write_only=True,
    )

    class Meta:
        model = StoryBookmark
        fields = ('id', 'story', 'story_id', 'note', 'created_at')
        read_only_fields = ('id', 'created_at')


class StoryLikeSerializer(serializers.ModelSerializer):
    """Serializer for story likes."""

    class Meta:
        model = StoryLike
        fields = ('id', 'story', 'created_at')
        read_only_fields = ('id', 'created_at')


class StoryFlagSerializer(serializers.ModelSerializer):
    """Serializer for story flags/reports."""

    user = UserSerializer(read_only=True)

    class Meta:
        model = StoryFlag
        fields = (
            'id',
            'user',
            'story',
            'reason',
            'details',
            'created_at',
            'resolved',
            'resolution_notes',
        )
        read_only_fields = ('id', 'user', 'story', 'created_at', 'resolved', 'resolution_notes')


class ReadingProgressSerializer(serializers.ModelSerializer):
    """Serializer for reading progress."""

    class Meta:
        model = ReadingProgress
        fields = (
            'id',
            'story',
            'progress_percent',
            'last_read_position',
            'completed',
            'created_at',
            'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')