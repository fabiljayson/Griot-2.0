from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView

from users.views import MeView

from .views import health_check, health_metrics, health_ready
from .views_analytics import (
    AdminUsersListView,
    DashboardSummaryView,
    EngagementAnalyticsView,
    GamificationAnalyticsView,
    QRAnalyticsView,
    StoryAnalyticsView,
    UserAnalyticsView,
)

urlpatterns = [
    # OpenAPI schema & docs.
    path('schema/', SpectacularAPIView.as_view(), name='schema'),
    path('docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),

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

    # VR: launch handoff to the Unity application, experience payloads and
    # session tracking. Not mounted under `/api/v1/` — this project has a
    # single unversioned `/api/` surface and one feature does not get to fork it.
    path('vr/', include('vr.urls')),
    path('notifications/', include('notifications.urls')),

    # Cultural-heritage crawler administration (§18). Admin-only: crawled
    # content reaches Flutter only after it has passed review (§19), so this
    # app deliberately exposes no public read surface.
    path('crawler/', include('heritage_crawl.urls')),

    # Griot AI: grounded question answering. The provider key stays on this
    # server — clients never talk to the model directly.
    path('ai/', include('griot_ai.urls')),

    # Phase 9: Admin analytics dashboard.
    path('analytics/dashboard/', DashboardSummaryView.as_view(), name='analytics-dashboard'),
    path('analytics/users/list/', AdminUsersListView.as_view(), name='analytics-users-list'),
    path('analytics/users/', UserAnalyticsView.as_view(), name='analytics-users'),
    path('analytics/stories/', StoryAnalyticsView.as_view(), name='analytics-stories'),
    path('analytics/gamification/', GamificationAnalyticsView.as_view(), name='analytics-gamification'),
    path('analytics/qr-codes/', QRAnalyticsView.as_view(), name='analytics-qr-codes'),
    path('analytics/engagement/', EngagementAnalyticsView.as_view(), name='analytics-engagement'),
]
