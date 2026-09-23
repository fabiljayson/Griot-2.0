"""
Admin analytics API views.

Provides endpoints for platform-wide analytics accessible only by admins
and institution managers.
"""
from django.contrib.auth import get_user_model
from django.db.models import Q
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .analytics import (
    get_user_stats,
    get_story_stats,
    get_gamification_stats,
    get_qr_stats,
    get_engagement_summary,
    get_dashboard_summary,
)
from .serializers_analytics import (
    UserStatsSerializer,
    StoryStatsSerializer,
    GamificationStatsSerializer,
    QRStatsSerializer,
    EngagementSummarySerializer,
    DashboardSummarySerializer,
    AdminUserListSerializer,
)

User = get_user_model()


class IsAdminOrManager(permissions.BasePermission):
    """Only admins and institution managers can access analytics."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in ('admin', 'institution_manager')


class DashboardSummaryView(APIView):
    """
    GET /api/analytics/dashboard/

    Complete dashboard summary with all analytics.
    Admin-only endpoint.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_dashboard_summary()
        serializer = DashboardSummarySerializer(data)
        return Response(serializer.data)


class UserAnalyticsView(APIView):
    """
    GET /api/analytics/users/

    User statistics and growth data.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_user_stats()
        serializer = UserStatsSerializer(data)
        return Response(serializer.data)


class AdminUsersListView(APIView):
    """
    GET /api/analytics/users/list/

    Every platform user (across all synced databases), newest first.
    Optional `?search=` filters by username, email or full name.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        queryset = User.objects.all().order_by('-date_joined', 'id')
        search = (request.query_params.get('search') or '').strip()
        if search:
            queryset = queryset.filter(
                Q(username__icontains=search)
                | Q(email__icontains=search)
                | Q(first_name__icontains=search)
                | Q(last_name__icontains=search)
            )
        serializer = AdminUserListSerializer(queryset, many=True)
        return Response(serializer.data)


class StoryAnalyticsView(APIView):
    """
    GET /api/analytics/stories/

    Story statistics, engagement, and growth.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_story_stats()
        serializer = StoryStatsSerializer(data)
        return Response(serializer.data)


class GamificationAnalyticsView(APIView):
    """
    GET /api/analytics/gamification/

    Gamification statistics (quizzes, badges, leaderboards).
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_gamification_stats()
        serializer = GamificationStatsSerializer(data)
        return Response(serializer.data)


class QRAnalyticsView(APIView):
    """
    GET /api/analytics/qr-codes/

    QR code and artifact scan statistics.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_qr_stats()
        serializer = QRStatsSerializer(data)
        return Response(serializer.data)


class EngagementAnalyticsView(APIView):
    """
    GET /api/analytics/engagement/

    High-level engagement metrics.
    """
    permission_classes = [IsAdminOrManager]

    def get(self, request):
        data = get_engagement_summary()
        serializer = EngagementSummarySerializer(data)
        return Response(serializer.data)
