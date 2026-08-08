from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

app_name = 'media'

router = DefaultRouter()
router.register(r'videos', views.VideoGenerationViewSet, basename='video-generation')
router.register(r'audio', views.AudioNarrationViewSet, basename='audio-narration')

urlpatterns = [
    path('', include(router.urls)),
    path('status/<str:job_type>/<int:job_id>/', views.MediaStatusView.as_view(), name='media-status'),
]