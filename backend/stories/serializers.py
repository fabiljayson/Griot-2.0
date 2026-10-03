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
from .services import MODERATOR_ROLES, resolve_status

User = get_user_model()


class StoryCategorySerializer(serializers.ModelSerializer):
    """Serializer for story categories."""

    story_count = serializers.SerializerMethodField()

    class Meta:
        model = StoryCategory
        fields = ('id', 'name', 'slug', 'description', 'icon', 'color', 'story_count')

    def get_story_count(self, obj) -> int:
        return obj.stories.filter(status=Story.Status.PUBLISHED).count()


class StoryListSerializer(serializers.ModelSerializer):
    """Compact serializer for story listings and discovery."""

    author = UserSerializer(read_only=True)
    categories = StoryCategorySerializer(many=True, read_only=True)
    is_bookmarked = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    # A story card can claim to be recorded oral tradition. The reader must be
    # able to tell seeded demo content from a community recording without
    # opening it, so the origin travels with the listing.
    attribution = serializers.CharField(read_only=True)
    is_synthetic_origin = serializers.BooleanField(read_only=True)

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
            'origin',
            'attribution',
            'is_synthetic_origin',
            'created_at',
            'published_at',
        )

    def get_is_bookmarked(self, obj) -> bool:
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryBookmark.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_is_liked(self, obj) -> bool:
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
    # The rejection reason. Moderators write it as the reason for a rejection
    # and it was previously read by *nobody* — no serializer, no template, no
    # Flutter model — so a rejected contributor saw `status: rejected` and had
    # no way to act on it. Visible to the author and to moderators only; it is
    # internal notes to everyone else.
    reviewer_notes = serializers.SerializerMethodField()
    # A model property returning a list of strings. `ReadOnlyField` leaves it
    # untyped in the schema, so drf-spectacular flags it and a generated client
    # has to guess. `ListField(child=CharField())` is the honest declaration
    # (there is no `many=True` on a plain field — that only exists on
    # serializer classes).
    tag_list = serializers.ListField(
        child=serializers.CharField(), read_only=True,
    )
    # Provenance and rights are part of the story, not an internal note: the
    # reader is entitled to know how this text was obtained and under what
    # licence it is shared. Derived rather than stored so they cannot drift
    # from `source`/`rights_holder`.
    attribution = serializers.CharField(read_only=True)
    is_synthetic_origin = serializers.BooleanField(read_only=True)

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
            'origin',
            'provenance_notes',
            'consent_status',
            'rights_holder',
            'licence',
            'recorded_at',
            'attribution',
            'is_synthetic_origin',
            'reviewer_notes',
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

    def get_is_bookmarked(self, obj) -> bool:
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryBookmark.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_is_liked(self, obj) -> bool:
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return StoryLike.objects.filter(
                user=request.user, story=obj
            ).exists()
        return False

    def get_reviewer_notes(self, obj) -> str:
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user is None or not user.is_authenticated:
            return ''
        if obj.author_id == user.id or user.role in MODERATOR_ROLES:
            return obj.reviewer_notes
        return ''

    def get_reading_progress(self, obj) -> dict | None:
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
            'origin',
            'provenance_notes',
            'rights_holder',
            'licence',
            'recorded_at',
        )
        # `consent_status` stays read-only: self-declared consent is exactly
        # the claim this app exists not to make on a community's behalf.
        #
        # `status` used to be read-only too, which meant the Flutter client's
        # `status: 'pending'` from the "submit for review" button was silently
        # discarded and the story stayed a draft — while the UI reported
        # success. It is writable now, but resolved through
        # `stories.services.resolve_status`, which is what stops an author
        # publishing their own story past the review queue.
        read_only_fields = ('consent_status',)

    def _resolve_status(self, validated_data):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if 'status' in validated_data and user is not None and user.is_authenticated:
            validated_data['status'] = resolve_status(user, validated_data['status'])

    def create(self, validated_data):
        self._resolve_status(validated_data)
        categories = validated_data.pop('categories', [])
        story = Story.objects.create(**validated_data)
        if categories:
            story.categories.set(categories)
        return story

    def update(self, instance, validated_data):
        self._resolve_status(validated_data)
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