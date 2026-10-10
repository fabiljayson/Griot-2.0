from django.contrib.auth import get_user_model
from rest_framework import serializers

from users.serializers import UserSerializer

from .models import (
    ModerationLog,
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
    StorySource,
    StoryVerification,
)
from .services import MODERATOR_ROLES, VERIFY_ACTIONS, log_status_change, resolve_status
from .trust import score_breakdown, trust_level

User = get_user_model()


class StoryCategorySerializer(serializers.ModelSerializer):
    """Serializer for story categories."""

    story_count = serializers.SerializerMethodField()

    class Meta:
        model = StoryCategory
        fields = ('id', 'name', 'slug', 'description', 'icon', 'color', 'story_count')

    def get_story_count(self, obj) -> int:
        return obj.stories.filter(status=Story.Status.PUBLISHED).count()


class StorySourceSerializer(serializers.ModelSerializer):
    """One documented source behind a story — the structured provenance."""

    verified_by = serializers.CharField(
        source='verified_by.username', read_only=True, default=None,
    )

    class Meta:
        model = StorySource
        fields = (
            'id',
            'story',
            'source_type',
            'name',
            'author',
            'institution',
            'url',
            'reference',
            'notes',
            'is_verified',
            'verified_by',
            'verified_at',
            'created_at',
            'updated_at',
        )
        read_only_fields = (
            'id',
            'story',
            'is_verified',
            'verified_by',
            'verified_at',
            'created_at',
            'updated_at',
        )


class StoryVerificationSerializer(serializers.ModelSerializer):
    """The evidence row behind the Cultural Trust Score.

    The score is read-only — it is derived from the criteria by
    `stories.trust`, and a writable score would be the one number on the
    page nobody could reproduce from the checklist beside it.
    """

    reviewer = serializers.CharField(
        source='reviewer.username', read_only=True, default=None,
    )
    trust_score = serializers.IntegerField(read_only=True)
    trust_level = serializers.SerializerMethodField()
    breakdown = serializers.SerializerMethodField()
    disclaimer = serializers.SerializerMethodField()

    class Meta:
        model = StoryVerification
        fields = (
            'source_verified',
            'community_validated',
            'expert_validated',
            'references_confirmed',
            'consistency_confirmed',
            'trust_score',
            'trust_level',
            'breakdown',
            'disclaimer',
            'reviewer',
            'notes',
            'verified_at',
            'updated_at',
        )
        read_only_fields = fields

    def get_trust_level(self, obj) -> str:
        return trust_level(obj.trust_score)

    def get_breakdown(self, obj) -> list:
        return score_breakdown(obj)

    def get_disclaimer(self, obj) -> str:
        return (
            'The Cultural Trust Score represents the strength of the '
            'available sources and verification evidence. It does not '
            'guarantee that every historical or cultural detail is '
            'objectively true.'
        )


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
    # Evidence strength travels with the card so a reader can weigh two
    # tales without opening both. Zero until a reviewer records evidence.
    trust_score = serializers.SerializerMethodField()
    trust_level = serializers.SerializerMethodField()

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
            'trust_score',
            'trust_level',
            'created_at',
            'published_at',
        )

    def get_trust_score(self, obj) -> int:
        verification = getattr(obj, 'verification', None)
        return verification.trust_score if verification else 0

    def get_trust_level(self, obj) -> str:
        return trust_level(self.get_trust_score(obj))

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
    # The provenance block: itemised sources, the evidence row, and the
    # score derived from it. `verification` is null until a reviewer has
    # touched the story — "no evidence recorded" is itself information.
    sources = StorySourceSerializer(many=True, read_only=True)
    verification = serializers.SerializerMethodField()
    trust_score = serializers.SerializerMethodField()
    trust_level = serializers.SerializerMethodField()

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
            'sources',
            'verification',
            'trust_score',
            'trust_level',
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
            'trust_score',
            'trust_level',
        )

    def get_verification(self, obj) -> dict | None:
        verification = getattr(obj, 'verification', None)
        if verification is None:
            return None
        return StoryVerificationSerializer(verification).data

    def get_trust_score(self, obj) -> int:
        verification = getattr(obj, 'verification', None)
        return verification.trust_score if verification else 0

    def get_trust_level(self, obj) -> str:
        return trust_level(self.get_trust_score(obj))

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
        # A story born in `pending` was submitted for review; leave a row in
        # the trail saying so, same as every later transition.
        log_status_change(
            self.context.get('request').user if self.context.get('request') else None,
            story, '', story.status,
        )
        return story

    def update(self, instance, validated_data):
        self._resolve_status(validated_data)
        before_status = instance.status
        categories = validated_data.pop('categories', None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        if categories is not None:
            instance.categories.set(categories)
        log_status_change(
            self.context.get('request').user if self.context.get('request') else None,
            instance, before_status, instance.status,
        )
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
    resolved_by = serializers.CharField(
        source='resolved_by.username', read_only=True, default=None,
    )
    reason_display = serializers.CharField(
        source='get_reason_display', read_only=True,
    )

    class Meta:
        model = StoryFlag
        fields = (
            'id',
            'user',
            'story',
            'reason',
            'reason_display',
            'details',
            'created_at',
            'resolved',
            'resolution_notes',
            'resolution_action',
            'resolved_by',
            'resolved_at',
        )
        read_only_fields = (
            'id',
            'user',
            'story',
            'reason_display',
            'created_at',
            'resolved',
            'resolution_notes',
            'resolution_action',
            'resolved_by',
            'resolved_at',
        )


class StoryVerifySerializer(serializers.Serializer):
    """Body of `POST /api/stories/{slug}/verify/`."""

    ACTION_CHOICES = tuple(VERIFY_ACTIONS.keys())

    action = serializers.ChoiceField(choices=ACTION_CHOICES)
    notes = serializers.CharField(required=False, allow_blank=True, default='')
    evidence = serializers.DictField(required=False, default=dict)


class ModerationLogSerializer(serializers.ModelSerializer):
    """One audit-trail row. Read-only: the trail is append-only."""

    actor = serializers.CharField(source='actor.username', read_only=True, default=None)
    action_display = serializers.CharField(
        source='get_action_display', read_only=True,
    )

    class Meta:
        model = ModerationLog
        fields = (
            'id',
            'story',
            'actor',
            'action',
            'action_display',
            'from_status',
            'to_status',
            'notes',
            'created_at',
        )
        read_only_fields = fields


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