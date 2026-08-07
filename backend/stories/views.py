from django.db.models import Q
from django.utils import timezone
from rest_framework import generics, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
)
from .serializers import (
    ReadingProgressSerializer,
    StoryCategorySerializer,
    StoryCreateUpdateSerializer,
    StoryDetailSerializer,
    StoryFlagSerializer,
    StoryListSerializer,
)


# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------
class IsContributorOrAbove(permissions.BasePermission):
    """Allow Contributors, Institution Managers, and Admins to create stories."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in ('contributor', 'institution_manager', 'admin')


class IsStoryOwnerOrReadOnly(permissions.BasePermission):
    """Allow story owners to edit/delete their own stories."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.author == request.user or request.user.role in (
            'institution_manager',
            'admin',
        )


# ---------------------------------------------------------------------------
# Story Category ViewSet
# ---------------------------------------------------------------------------
class StoryCategoryViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/stories/categories/ — list and retrieve story categories."""

    queryset = StoryCategory.objects.all()
    serializer_class = StoryCategorySerializer
    permission_classes = [permissions.AllowAny]
    lookup_field = 'slug'


# ---------------------------------------------------------------------------
# Story ViewSet
# ---------------------------------------------------------------------------
class StoryViewSet(viewsets.ModelViewSet):
    """Story CRUD with search, filtering, and actions.

    Endpoints:
        GET    /api/stories/              — list published stories
        POST   /api/stories/              — create a story (contributors+)
        GET    /api/stories/{slug}/       — retrieve story detail
        PUT    /api/stories/{slug}/       — update story
        DELETE /api/stories/{slug}/       — delete story
        POST   /api/stories/{slug}/bookmark/  — toggle bookmark
        POST   /api/stories/{slug}/like/      — toggle like
        POST   /api/stories/{slug}/flag/      — flag for inaccuracy
        POST   /api/stories/{slug}/progress/  — update reading progress
        GET    /api/stories/my/           — current user's stories
        GET    /api/stories/bookmarks/    — current user's bookmarks
    """

    lookup_field = 'slug'

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            permission_classes = [permissions.AllowAny]
        elif self.action in ('create',):
            permission_classes = [permissions.IsAuthenticated, IsContributorOrAbove]
        elif self.action in ('update', 'partial_update', 'destroy'):
            permission_classes = [permissions.IsAuthenticated, IsStoryOwnerOrReadOnly]
        else:
            permission_classes = [permissions.IsAuthenticated]
        return [p() for p in permission_classes]

    def get_queryset(self):
        queryset = Story.objects.select_related('author').prefetch_related('categories')

        # Default: show published stories for anonymous users
        user = self.request.user
        if not user.is_authenticated:
            queryset = queryset.filter(status=Story.Status.PUBLISHED)
        elif user.role in ('institution_manager', 'admin'):
            # Admins see everything
            pass
        elif user.role == 'contributor':
            # Contributors see published + their own drafts/pending
            queryset = queryset.filter(
                Q(status=Story.Status.PUBLISHED) | Q(author=user)
            )
        else:
            # Visitors see published only
            queryset = queryset.filter(status=Story.Status.PUBLISHED)

        # Search
        search = self.request.query_params.get('search', '').strip()
        if search:
            queryset = queryset.filter(
                Q(title__icontains=search)
                | Q(content__icontains=search)
                | Q(summary__icontains=search)
                | Q(tags__icontains=search)
            )

        # Language filter
        language = self.request.query_params.get('language', '').strip()
        if language:
            queryset = queryset.filter(language=language)

        # Category filter
        category = self.request.query_params.get('category', '').strip()
        if category:
            queryset = queryset.filter(categories__slug=category)

        # Region filter
        region = self.request.query_params.get('region', '').strip()
        if region:
            queryset = queryset.filter(region__icontains=region)

        # Sorting
        sort = self.request.query_params.get('sort', '-created_at')
        if sort in ('created_at', '-created_at', 'title', '-title', 'view_count', '-view_count'):
            queryset = queryset.order_by(sort)

        return queryset.distinct()

    def get_serializer_class(self):
        if self.action == 'list':
            return StoryListSerializer
        elif self.action in ('create', 'update', 'partial_update'):
            return StoryCreateUpdateSerializer
        return StoryDetailSerializer

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        # Increment view count
        Story.objects.filter(pk=instance.pk).update(view_count=instance.view_count + 1)
        instance.refresh_from_db()
        serializer = self.get_serializer(instance)
        return Response(serializer.data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def my(self, request):
        """GET /api/stories/my/ — current user's stories."""
        stories = Story.objects.filter(author=request.user).order_by('-created_at')
        serializer = StoryListSerializer(stories, many=True, context={'request': request})
        return Response(serializer.data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def bookmarks(self, request):
        """GET /api/stories/bookmarks/ — current user's bookmarked stories."""
        bookmarks = StoryBookmark.objects.filter(user=request.user).select_related('story')
        stories = [b.story for b in bookmarks]
        serializer = StoryListSerializer(stories, many=True, context={'request': request})
        return Response(serializer.data)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def bookmark(self, request, slug=None):
        """POST /api/stories/{slug}/bookmark/ — toggle bookmark."""
        story = self.get_object()
        bookmark, created = StoryBookmark.objects.get_or_create(
            user=request.user,
            story=story,
        )
        if not created:
            bookmark.delete()
            Story.objects.filter(pk=story.pk).update(bookmark_count=max(0, story.bookmark_count - 1))
            return Response({'bookmarked': False}, status=status.HTTP_200_OK)
        Story.objects.filter(pk=story.pk).update(bookmark_count=story.bookmark_count + 1)
        return Response({'bookmarked': True}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def like(self, request, slug=None):
        """POST /api/stories/{slug}/like/ — toggle like."""
        story = self.get_object()
        like, created = StoryLike.objects.get_or_create(
            user=request.user,
            story=story,
        )
        if not created:
            like.delete()
            Story.objects.filter(pk=story.pk).update(like_count=max(0, story.like_count - 1))
            return Response({'liked': False}, status=status.HTTP_200_OK)
        Story.objects.filter(pk=story.pk).update(like_count=story.like_count + 1)
        return Response({'liked': True}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def flag(self, request, slug=None):
        """POST /api/stories/{slug}/flag/ — flag story for cultural inaccuracy."""
        story = self.get_object()
        serializer = StoryFlagSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(user=request.user, story=story)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def progress(self, request, slug=None):
        """POST /api/stories/{slug}/progress/ — update reading progress."""
        story = self.get_object()
        progress, _ = ReadingProgress.objects.get_or_create(
            user=request.user,
            story=story,
        )
        serializer = ReadingProgressSerializer(progress, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


# ---------------------------------------------------------------------------
# Category List (standalone endpoint)
# ---------------------------------------------------------------------------
class StoryCategoryListView(generics.ListAPIView):
    """GET /api/stories/categories/ — list all story categories."""

    queryset = StoryCategory.objects.all()
    serializer_class = StoryCategorySerializer
    permission_classes = [permissions.AllowAny]