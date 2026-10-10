from django.urls import path

from . import views

app_name = 'vr'

urlpatterns = [
    # Ordered most-specific first: `launch/exchange/` must not be swallowed by
    # a `launch/<something>` route, and the sessions routes keep their literal
    # prefix ahead of the `<int:pk>` one.
    path('launch/', views.VRLaunchView.as_view(), name='launch'),
    path(
        'launch/exchange/',
        views.VRLaunchExchangeView.as_view(),
        name='launch-exchange',
    ),
    path('experiences/', views.VRExperienceListView.as_view(), name='experience-list'),
    path(
        'experiences/<str:key>/',
        views.VRExperienceDetailView.as_view(),
        name='experience-detail',
    ),
    path(
        'artifacts/<str:key>/',
        views.VRArtifactDetailView.as_view(),
        name='artifact-detail',
    ),
    path('locations/', views.VRLocationListView.as_view(), name='location-list'),
    path('progress/', views.VRProgressView.as_view(), name='progress'),
    path('sessions/', views.VRSessionStartView.as_view(), name='session-start'),
    path(
        'sessions/<int:pk>/complete/',
        views.VRSessionCompleteView.as_view(),
        name='session-complete',
    ),
]
