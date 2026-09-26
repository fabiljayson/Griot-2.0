from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    QuizQuestion,
    UserBadge,
    UserProfile,
)
from .services import streaks
from .serializers import (
    BadgeSerializer,
    CertificateSerializer,
    QuizAttemptCreateSerializer,
    QuizAttemptDetailSerializer,
    QuizDetailSerializer,
    QuizListSerializer,
    QuizSubmitAnswerSerializer,
    UserBadgeSerializer,
    UserProfileSerializer,
)


class IsAuthenticatedOrReadOnly(permissions.BasePermission):
    def has_permission(self, request, view):
        if request.method in permissions.SAFE_METHODS:
            return True
        return request.user and request.user.is_authenticated


class QuizViewSet(viewsets.ReadOnlyModelViewSet):
    """Quiz CRUD — read only, quizzes created via admin."""

    permission_classes = [IsAuthenticatedOrReadOnly]

    def get_serializer_class(self):
        if self.action == 'retrieve':
            return QuizDetailSerializer
        return QuizListSerializer

    def get_queryset(self):
        qs = Quiz.objects.select_related('story').prefetch_related('questions')
        is_staff = self.request.user.is_authenticated and (
            self.request.user.role in ('admin', 'institution_manager')
        )
        if not is_staff:
            qs = qs.filter(is_published=True)

        # The story reader resolves a quiz by story id, so let it ask for
        # exactly one story's quiz instead of downloading the whole catalogue.
        story_id = self.request.query_params.get('story')
        if story_id:
            try:
                story_id = int(story_id)
            except (TypeError, ValueError):
                return qs.none()
            qs = qs.filter(story_id=story_id)
        return qs

    @action(detail=True, methods=['post'])
    def start(self, request, pk=None):
        """Start a new quiz attempt."""
        quiz = self.get_object()

        if not request.user.is_authenticated:
            return Response(
                {'error': 'Authentication required'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # Check for existing in-progress attempt
        existing = QuizAttempt.objects.filter(
            user=request.user,
            quiz=quiz,
            status=QuizAttempt.Status.IN_PROGRESS,
        ).first()

        if existing:
            return Response(QuizAttemptDetailSerializer(existing).data)

        # Create new attempt
        attempt = QuizAttempt.objects.create(
            user=request.user,
            quiz=quiz,
            total_questions=quiz.question_count,
        )

        return Response(
            QuizAttemptDetailSerializer(attempt).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'])
    def submit_answer(self, request, pk=None):
        """Submit an answer for a quiz question."""
        quiz = self.get_object()
        serializer = QuizSubmitAnswerSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        question_id = serializer.validated_data['question_id']
        selected_answer = serializer.validated_data['selected_answer']

        # Get the active attempt
        attempt = QuizAttempt.objects.filter(
            user=request.user,
            quiz=quiz,
            status=QuizAttempt.Status.IN_PROGRESS,
        ).first()

        if not attempt:
            return Response(
                {'error': 'No active quiz attempt. Start the quiz first.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Get the question
        question = get_object_or_404(QuizQuestion, id=question_id, quiz=quiz)

        # Check if already answered
        existing_answers = attempt.answers or []
        if any(a.get('question_id') == question_id for a in existing_answers):
            return Response(
                {'error': 'Question already answered'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Grade the answer
        is_correct = selected_answer == question.correct_answer

        # Record the answer
        answer_record = {
            'question_id': question_id,
            'selected_answer': selected_answer,
            'correct_answer': question.correct_answer,
            'is_correct': is_correct,
            'explanation': question.explanation,
        }
        existing_answers.append(answer_record)
        attempt.answers = existing_answers
        attempt.save(update_fields=['answers'])

        return Response({
            'is_correct': is_correct,
            'correct_answer': question.correct_answer,
            'explanation': question.explanation,
            'answered_count': len(existing_answers),
            'total_questions': attempt.total_questions,
        })

    @action(detail=True, methods=['post'])
    def finish(self, request, pk=None):
        """Finish and grade a quiz attempt."""
        quiz = self.get_object()

        attempt = QuizAttempt.objects.filter(
            user=request.user,
            quiz=quiz,
            status=QuizAttempt.Status.IN_PROGRESS,
        ).first()

        if not attempt:
            return Response(
                {'error': 'No active quiz attempt'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Calculate score
        attempt.calculate_score()
        attempt.status = QuizAttempt.Status.COMPLETED
        attempt.completed_at = timezone.now()
        attempt.time_taken_seconds = int(
            (attempt.completed_at - attempt.started_at).total_seconds()
        )

        # Award XP if passed. Attempting a quiz is activity either way, so the
        # streak advances even when the reader did not pass.
        if attempt.passed:
            attempt.xp_earned = quiz.xp_reward
            streaks.grant_xp_and_stats(
                request.user, xp=quiz.xp_reward, quizzes_passed=1
            )
            # Check for badge eligibility
            self._check_badges(request.user)
        else:
            streaks.record_activity(request.user)

        attempt.save()

        return Response(QuizAttemptDetailSerializer(attempt).data)

    def _check_badges(self, user):
        """Check and award any eligible badges."""
        profile, _ = UserProfile.objects.get_or_create(user=user)
        earned_badge_ids = UserBadge.objects.filter(user=user).values_list('badge_id', flat=True)

        for badge in Badge.objects.filter(is_active=True).exclude(id__in=earned_badge_ids):
            earned = False

            if badge.xp_required and profile.total_xp >= badge.xp_required:
                earned = True
            if badge.stories_read_required and profile.stories_read >= badge.stories_read_required:
                earned = True
            if badge.quizzes_passed_required and profile.quizzes_passed >= badge.quizzes_passed_required:
                earned = True

            if earned:
                UserBadge.objects.create(user=user, badge=badge)


class QuizAttemptViewSet(viewsets.ReadOnlyModelViewSet):
    """User's quiz attempts."""

    serializer_class = QuizAttemptDetailSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return QuizAttempt.objects.filter(
            user=self.request.user,
        ).select_related('quiz', 'quiz__story')


class BadgeViewSet(viewsets.ReadOnlyModelViewSet):
    """List all badges and check earned status."""

    serializer_class = BadgeSerializer
    permission_classes = [permissions.AllowAny]
    queryset = Badge.objects.filter(is_active=True)

    def get_queryset(self):
        qs = super().get_queryset()
        # Hide secret badges unless earned
        if self.request.user.is_authenticated:
            earned_ids = UserBadge.objects.filter(
                user=self.request.user,
            ).values_list('badge_id', flat=True)
            return qs.filter(Q(is_secret=False) | Q(id__in=earned_ids))
        return qs.filter(is_secret=False)


class UserBadgeViewSet(viewsets.ReadOnlyModelViewSet):
    """User's earned badges."""

    serializer_class = UserBadgeSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return UserBadge.objects.filter(
            user=self.request.user,
        ).select_related('badge')


class UserProfileView(generics.RetrieveAPIView):
    """Get the current user's gamification profile."""

    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        profile, _ = UserProfile.objects.get_or_create(user=self.request.user)
        return profile


class ActivitySerializer(serializers.Serializer):
    """Body of the activity ping.

    ``timezone`` is the device's IANA zone. The streak is decided on the
    reader's calendar, so without it a reader east of UTC has their day counted
    against the wrong date for part of every evening.
    """

    timezone = serializers.CharField(required=False, allow_blank=True, max_length=64)


class RecordActivityView(generics.CreateAPIView):
    """POST /api/gamification/activity/ — count today as an active day.

    Sent when the app opens, which is what makes "any activity keeps a streak"
    true: reading is not the only way to show up, and a reader who opens the app
    but does not finish a story should not silently lose a run.

    Idempotent, and returns the whole profile so the client can reconcile its
    streak display in the same round trip that advanced it.
    """

    serializer_class = ActivitySerializer
    permission_classes = [permissions.IsAuthenticated]

    def create(self, request, *args, **kwargs):
        payload = self.get_serializer(data=request.data)
        payload.is_valid(raise_exception=True)
        streaks.record_activity(
            request.user, timezone_name=payload.validated_data.get('timezone')
        )
        # The reader is here, so deliver whatever is waiting for them. Idempotent,
        # and it is the only place a reader who never opens the app is skipped —
        # which costs nothing, since they could not have read it either way.
        from notifications import services as notification_services

        notification_services.sync_for_user(request.user)

        profile = UserProfile.objects.get(user=request.user)
        return Response(
            UserProfileSerializer(profile).data, status=status.HTTP_200_OK
        )


class LeaderboardView(generics.ListAPIView):
    """Top users by XP."""

    permission_classes = [permissions.AllowAny]

    def get(self, request):
        profiles = UserProfile.objects.select_related('user').order_by('-total_xp')[:20]
        data = []
        for i, profile in enumerate(profiles, 1):
            data.append({
                'rank': i,
                'username': profile.user.username,
                'level': profile.level,
                'total_xp': profile.total_xp,
                'stories_read': profile.stories_read,
                'quizzes_passed': profile.quizzes_passed,
                'current_streak': profile.current_streak,
            })
        return Response(data)


class CertificateViewSet(viewsets.ReadOnlyModelViewSet):
    """User's certificates."""

    serializer_class = CertificateSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Certificate.objects.filter(user=self.request.user)
