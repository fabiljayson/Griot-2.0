from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    StoryCategoryViewSet,
    StorySourceDetailView,
    StorySourceListCreateView,
    StoryViewSet,
)

app_name = 'stories'

router = DefaultRouter()
router.register(r'stories', StoryViewSet, basename='story')
router.register(r'categories', StoryCategoryViewSet, basename='category')

urlpatterns = [
    # Provenance endpoints. Listed before the router for readability; the
    # router's detail pattern (`stories/{slug}/$`) cannot swallow them —
    # it stops at the slug.
    path(
        'stories/<slug:slug>/sources/',
        StorySourceListCreateView.as_view(),
        name='story-sources',
    ),
    path(
        'stories/<slug:slug>/sources/<int:pk>/',
        StorySourceDetailView.as_view(),
        name='story-source-detail',
    ),
    path('', include(router.urls)),
]