from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

app_name = 'gamification'

router = DefaultRouter()
router.register(r'quizzes', views.QuizViewSet, basename='quiz')
router.register(r'attempts', views.QuizAttemptViewSet, basename='quiz-attempt')
router.register(r'badges', views.BadgeViewSet, basename='badge')
router.register(r'user-badges', views.UserBadgeViewSet, basename='user-badge')
router.register(r'certificates', views.CertificateViewSet, basename='certificate')

urlpatterns = [
    path('', include(router.urls)),
    path('profile/', views.UserProfileView.as_view(), name='user-profile'),
    path('leaderboard/', views.LeaderboardView.as_view(), name='leaderboard'),
]
