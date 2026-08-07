from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import StoryCategoryListView, StoryCategoryViewSet, StoryViewSet

app_name = 'stories'

router = DefaultRouter()
router.register(r'stories', StoryViewSet, basename='story')
router.register(r'categories', StoryCategoryViewSet, basename='category')

urlpatterns = [
    path('', include(router.urls)),
]