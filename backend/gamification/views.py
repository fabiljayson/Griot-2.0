from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions, status, viewsets
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
        if self.request.user.is_authenticated and self.request.user.role in (
            'admin', 'institution_manager',
        ):
            return qs
        return qs.filter(is_published=True)

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

        # Award XP if passed
        if attempt.passed:
            attempt.xp_earned = quiz.xp_reward
            # Update user profile
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            profile.add_xp(quiz.xp_reward)
            profile.quizzes_passed += 1
            profile.total_quiz_xp += quiz.xp_reward
            profile.save(update_fields=[
                'quizzes_passed', 'total_quiz_xp', 'updated_at',
            ])
            # Check for badge eligibility
            self._check_badges(request.user)

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
