from rest_framework import serializers

from .models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    QuizQuestion,
    UserBadge,
    UserProfile,
)


class QuizQuestionSerializer(serializers.ModelSerializer):
    """Serializer for quiz questions (hides correct answer)."""

    class Meta:
        model = QuizQuestion
        fields = [
            'id',
            'question_text',
            'option_a',
            'option_b',
            'option_c',
            'option_d',
            'difficulty',
            'order',
        ]


class QuizDetailSerializer(serializers.ModelSerializer):
    """Serializer for quiz detail with questions."""

    questions = QuizQuestionSerializer(many=True, read_only=True)
    story_title = serializers.CharField(source='story.title', read_only=True)
    question_count = serializers.IntegerField(read_only=True)
    xp_reward = serializers.IntegerField(read_only=True)

    class Meta:
        model = Quiz
        fields = [
            'id',
            'title',
            'description',
            'story',
            'story_title',
            'passing_score',
            'time_limit_minutes',
            'question_count',
            'xp_reward',
            'questions',
            'is_published',
            'created_at',
        ]


class QuizListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for quiz list views."""

    story_title = serializers.CharField(source='story.title', read_only=True)
    question_count = serializers.IntegerField(read_only=True)
    xp_reward = serializers.IntegerField(read_only=True)
    best_score = serializers.SerializerMethodField()

    class Meta:
        model = Quiz
        fields = [
            'id',
            'title',
            'story',
            'story_title',
            'passing_score',
            'question_count',
            'xp_reward',
            'best_score',
        ]

    def get_best_score(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            attempt = obj.attempts.filter(
                user=request.user,
                status='completed',
            ).order_by('-score').first()
            return attempt.score if attempt else None
        return None


class QuizSubmitAnswerSerializer(serializers.Serializer):
    """Serializer for submitting a quiz answer."""

    question_id = serializers.IntegerField()
    selected_answer = serializers.ChoiceField(choices=['a', 'b', 'c', 'd'])


class QuizAttemptCreateSerializer(serializers.Serializer):
    """Serializer for creating a quiz attempt."""

    quiz_id = serializers.IntegerField()


class QuizAttemptDetailSerializer(serializers.ModelSerializer):
    """Serializer for quiz attempt details."""

    quiz_title = serializers.CharField(source='quiz.title', read_only=True)
    story_title = serializers.CharField(source='quiz.story.title', read_only=True)

    class Meta:
        model = QuizAttempt
        fields = [
            'id',
            'quiz',
            'quiz_title',
            'story_title',
            'score',
            'correct_count',
            'total_questions',
            'passed',
            'xp_earned',
            'status',
            'answers',
            'started_at',
            'completed_at',
            'time_taken_seconds',
        ]
        read_only_fields = fields


class BadgeSerializer(serializers.ModelSerializer):
    """Serializer for badges."""

    earned = serializers.SerializerMethodField()

    class Meta:
        model = Badge
        fields = [
            'id',
            'name',
            'slug',
            'description',
            'emoji',
            'category',
            'xp_required',
            'color',
            'is_secret',
            'earned',
        ]

    def get_earned(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return UserBadge.objects.filter(
                user=request.user, badge=obj,
            ).exists()
        return False


class UserBadgeSerializer(serializers.ModelSerializer):
    """Serializer for earned badges."""

    badge_name = serializers.CharField(source='badge.name', read_only=True)
    badge_emoji = serializers.CharField(source='badge.emoji', read_only=True)
    badge_description = serializers.CharField(source='badge.description', read_only=True)
    badge_category = serializers.CharField(source='badge.category', read_only=True)

    class Meta:
        model = UserBadge
        fields = [
            'id',
            'badge',
            'badge_name',
            'badge_emoji',
            'badge_description',
            'badge_category',
            'earned_at',
        ]


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for user gamification profile."""

    username = serializers.CharField(source='user.username', read_only=True)
    badges_count = serializers.SerializerMethodField()
    recent_badges = serializers.SerializerMethodField()

    class Meta:
        model = UserProfile
        fields = [
            'id',
            'username',
            'total_xp',
            'level',
            'stories_read',
            'stories_completed',
            'quizzes_passed',
            'total_quiz_xp',
            'current_streak',
            'longest_streak',
            'xp_for_next_level',
            'xp_progress',
            'badges_count',
            'recent_badges',
            'updated_at',
        ]

    def get_badges_count(self, obj):
        return UserBadge.objects.filter(user=obj.user).count()

    def get_recent_badges(self, obj):
        recent = UserBadge.objects.filter(user=obj.user).select_related('badge')[:5]
        return UserBadgeSerializer(recent, many=True).data


class CertificateSerializer(serializers.ModelSerializer):
    """Serializer for certificates."""

    class Meta:
        model = Certificate
        fields = [
            'id',
            'certificate_type',
            'title',
            'description',
            'certificate_number',
            'issued_at',
            'stories_read',
            'quizzes_passed',
            'level_achieved',
            'pdf_url',
        ]
        read_only_fields = fields
