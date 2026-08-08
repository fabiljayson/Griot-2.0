from django.urls import include, path

from users.views import MeView

from .views import health_check, health_metrics, health_ready
from .views_analytics import (
    DashboardSummaryView,
    UserAnalyticsView,
    StoryAnalyticsView,
    GamificationAnalyticsView,
    QRAnalyticsView,
    EngagementAnalyticsView,
)

urlpatterns = [
    # Phase 10 observability probes: liveness, readiness, metrics.
    path('health/', health_check, name='health'),
    path('health/ready/', health_ready, name='health-ready'),
    path('health/metrics/', health_metrics, name='health-metrics'),

    # Phase 2: authentication & user management.
    path('auth/', include('users.urls')),

    # Current-user profile & delete-account (Task 2.3) at the documented path.
    path('users/me/', MeView.as_view(), name='me'),

    # Phase 3: story endpoints.
    path('', include('stories.urls')),

    # Phase 4: media & AI generation endpoints.
    path('media/', include('media_app.urls')),

    # Phase 5: artifact / QR code engine & deep linking.
    path('', include('qr_codes.urls')),

    # Phase 6: gamification, quizzes & certification.
    path('gamification/', include('gamification.urls')),

    # Phase 9: Admin analytics dashboard.
    path('analytics/dashboard/', DashboardSummaryView.as_view(), name='analytics-dashboard'),
    path('analytics/users/', UserAnalyticsView.as_view(), name='analytics-users'),
    path('analytics/stories/', StoryAnalyticsView.as_view(), name='analytics-stories'),
    path('analytics/gamification/', GamificationAnalyticsView.as_view(), name='analytics-gamification'),
    path('analytics/qr-codes/', QRAnalyticsView.as_view(), name='analytics-qr-codes'),
    path('analytics/engagement/', EngagementAnalyticsView.as_view(), name='analytics-engagement'),
]
