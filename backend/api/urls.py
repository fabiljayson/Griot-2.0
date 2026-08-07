from django.urls import include, path

from users.views import MeView

from .views import health_check

urlpatterns = [
    # Baseline liveness probe.
    path('health/', health_check, name='health'),

    # Phase 2: authentication & user management.
    path('auth/', include('users.urls')),

    # Current-user profile & delete-account (Task 2.3) at the documented path.
    path('users/me/', MeView.as_view(), name='me'),

    # Phase 3: story endpoints.
    path('', include('stories.urls')),

    # Phase 4: media & AI generation endpoints.
    path('media/', include('media_app.urls')),

    # Phase 5: artifact / QR endpoints will be mounted at /api/artifacts/...
    # Phase 6: quiz / gamification endpoints will be mounted at /api/gamification/...
]
