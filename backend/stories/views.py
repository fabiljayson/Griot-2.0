from django.db.models import Q, Count, F
from django.utils import timezone
from django.utils.timesince import timesince
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
    StoryShare,
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


class IsAdminOrManager(permissions.BasePermission):
    """Only admins and institution managers can moderate content."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in ('admin', 'institution_manager')


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
        GET    /api/stories/moderation-queue/ — flagged stories (admin only)
        POST   /api/stories/{slug}/moderate/  — resolve flags (admin only)
    """

    lookup_field = 'slug'

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            permission_classes = [permissions.AllowAny]
        elif self.action in ('create',):
            permission_classes = [permissions.IsAuthenticated, IsContributorOrAbove]
        elif self.action in ('update', 'partial_update', 'destroy'):
            permission_classes = [permissions.IsAuthenticated, IsStoryOwnerOrReadOnly]
        elif self.action in ('moderation_queue', 'moderate'):
            permission_classes = [IsAdminOrManager]
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

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def recently_read(self, request):
        """GET /api/stories/recently-read/ — user's recently read stories."""
        progress_records = ReadingProgress.objects.filter(
            user=request.user,
        ).select_related('story', 'story__author').order_by('-updated_at')[:20]

        data = []
        for record in progress_records:
            story = record.story
            data.append({
                'id': story.id,
                'slug': story.slug,
                'title': story.title,
                'summary': story.summary,
                'language': story.language,
                'region': story.region,
                'cover_image': story.cover_image.url if story.cover_image else None,
                'estimated_read_time': story.estimated_read_time,
                'progress_percent': record.progress_percent,
                'completed': record.completed,
                'last_read_at': record.updated_at.isoformat(),
            })

        return Response(data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.IsAuthenticated])
    def continue_reading(self, request):
        """GET /api/stories/continue-reading/ — stories in progress (not completed)."""
        progress_records = ReadingProgress.objects.filter(
            user=request.user,
            completed=False,
            progress_percent__gt=0,
        ).select_related('story', 'story__author').order_by('-updated_at')[:5]

        data = []
        for record in progress_records:
            story = record.story
            data.append({
                'id': story.id,
                'slug': story.slug,
                'title': story.title,
                'summary': story.summary,
                'language': story.language,
                'region': story.region,
                'cover_image': story.cover_image.url if story.cover_image else None,
                'estimated_read_time': story.estimated_read_time,
                'progress_percent': record.progress_percent,
                'last_read_at': record.updated_at.isoformat(),
            })

        return Response(data)

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

    @action(detail=False, methods=['get'])
    def moderation_queue(self, request):
        """GET /api/stories/moderation-queue/ — unresolved flagged stories.

        Groups unresolved flags by story so moderators can review and act on
        them from the admin dashboard.
        """
        flags = StoryFlag.objects.filter(resolved=False).select_related(
            'story', 'story__author', 'user',
        ).order_by('-created_at')

        grouped = {}
        for flag in flags:
            story = flag.story
            entry = grouped.setdefault(story.id, {
                'story_id': story.id,
                'slug': story.slug,
                'title': story.title,
                'status': story.status,
                'author_username': story.author.username,
                'flags': [],
            })
            entry['flags'].append({
                'id': flag.id,
                'reason': flag.reason,
                'reason_display': flag.get_reason_display(),
                'details': flag.details,
                'reporter': flag.user.username,
                'created_at': flag.created_at.isoformat(),
            })

        return Response(list(grouped.values()))

    @action(detail=True, methods=['post'])
    def moderate(self, request, slug=None):
        """POST /api/stories/{slug}/moderate/ — resolve flags on a story.

        Body:
            action: 'remove' (archive the story) | 'dismiss' (keep the story)
            notes:  optional resolution notes
        """
        story = self.get_object()
        action = request.data.get('action', '')
        notes = request.data.get('notes', '')

        if action not in ('remove', 'dismiss'):
            return Response(
                {'error': 'action must be "remove" or "dismiss"'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Resolve every open flag on the story.
        StoryFlag.objects.filter(story=story, resolved=False).update(
            resolved=True,
            resolution_notes=notes,
        )

        if action == 'remove':
            story.status = Story.Status.ARCHIVED
            story.reviewer_notes = notes
            story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])

        return Response({
            'story_id': story.id,
            'slug': story.slug,
            'status': story.status,
            'action': action,
            'resolved_flags': StoryFlag.objects.filter(
                story=story, resolved=True,
            ).count(),
        })

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

    @action(detail=True, methods=['post'])
    def share(self, request, slug=None):
        """POST /api/stories/{slug}/share/ — track a story share."""
        story = self.get_object()
        platform = request.data.get('platform', 'other')
        
        # Create share record
        StoryShare.objects.create(
            story=story,
            user=request.user if request.user.is_authenticated else None,
            platform=platform,
            ip_address=self._get_client_ip(request),
        )
        
        # Increment share count
        Story.objects.filter(pk=story.pk).update(share_count=F('share_count') + 1)
        
        # Generate share URL
        share_url = request.build_absolute_uri(f'/story/{story.slug}')
        share_text = f'Check out "{story.title}" on African Teller! 🌍📖'
        
        return Response({
            'share_url': share_url,
            'share_text': share_text,
            'story_title': story.title,
        })

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny])
    def trending(self, request):
        """GET /api/stories/trending/ — trending stories by views and likes."""
        # Get stories from the last 7 days, ordered by engagement
        week_ago = timezone.now() - timezone.timedelta(days=7)
        stories = Story.objects.filter(
            status=Story.Status.PUBLISHED,
            created_at__gte=week_ago,
        ).select_related('author').prefetch_related('categories').annotate(
            engagement=Count('likes') + Count('bookmarks') + F('view_count'),
        ).order_by('-engagement')[:10]

        serializer = StoryListSerializer(stories, many=True, context={'request': request})
        return Response(serializer.data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny])
    def popular(self, request):
        """GET /api/stories/popular/ — all-time popular stories."""
        stories = Story.objects.filter(
            status=Story.Status.PUBLISHED,
        ).select_related('author').prefetch_related('categories').order_by(
            '-view_count', '-like_count'
        )[:10]

        serializer = StoryListSerializer(stories, many=True, context={'request': request})
        return Response(serializer.data)

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny])
    def discover(self, request):
        """GET /api/stories/discover/ — curated discovery feed."""
        # Mix of featured, recent, and diverse content
        featured = Story.objects.filter(
            status=Story.Status.PUBLISHED,
            view_count__gte=10,
        ).select_related('author').prefetch_related('categories').order_by('-view_count')[:3]

        recent = Story.objects.filter(
            status=Story.Status.PUBLISHED,
        ).select_related('author').prefetch_related('categories').order_by('-created_at')[:3]

        # Diverse by region
        regions = Story.objects.filter(
            status=Story.Status.PUBLISHED,
            region__isnull=False,
        ).values_list('region', flat=True).distinct()[:6]

        diverse = []
        for region in regions:
            story = Story.objects.filter(
                status=Story.Status.PUBLISHED,
                region=region,
            ).select_related('author').order_by('-view_count').first()
            if story:
                diverse.append(story)

        # Combine and deduplicate
        all_stories = list(featured) + list(recent) + diverse
        seen_ids = set()
        unique_stories = []
        for story in all_stories:
            if story.id not in seen_ids:
                seen_ids.add(story.id)
                unique_stories.append(story)

        serializer = StoryListSerializer(unique_stories[:10], many=True, context={'request': request})
        return Response(serializer.data)

    def _get_client_ip(self, request):
        x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded:
            return x_forwarded.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR')


# ---------------------------------------------------------------------------
# Category List (standalone endpoint)
# ---------------------------------------------------------------------------
class StoryCategoryListView(generics.ListAPIView):
    """GET /api/stories/categories/ — list all story categories."""

    queryset = StoryCategory.objects.all()
    serializer_class = StoryCategorySerializer
    permission_classes = [permissions.AllowAny]