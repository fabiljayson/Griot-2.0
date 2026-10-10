from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Count, F, Q
from django.db.models.functions import Greatest
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from config.client_ip import get_client_ip

from . import services as story_services
from .models import (
    ModerationLog,
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
    StoryShare,
    StorySource,
    StoryVerification,
)
from .serializers import (
    ReadingProgressSerializer,
    StoryCategorySerializer,
    StoryCreateUpdateSerializer,
    StoryDetailSerializer,
    StoryFlagSerializer,
    StoryListSerializer,
    StorySourceSerializer,
    StoryVerifySerializer,
)
from .trust import score_breakdown, trust_level


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
        POST   /api/stories/{slug}/request_consent/ — "I have asked" (author)
        POST   /api/stories/{slug}/record_consent/ — record the answer (moderator)
        POST   /api/stories/{slug}/progress/  — update reading progress
        GET    /api/stories/my/           — current user's stories
        GET    /api/stories/bookmarks/    — current user's bookmarks
        GET    /api/stories/moderation_queue/ — flagged stories (admin only)
        POST   /api/stories/{slug}/moderate/  — resolve flags (admin only)
        GET    /api/stories/consent_queue/ — awaiting a consent decision (admin only)
        GET    /api/stories/verification_queue/ — awaiting review (admin only)
        POST   /api/stories/{slug}/verify/ — approve/reject/request changes (admin only)
        POST   /api/stories/{slug}/verify_source/ — confirm a source (admin only)
        GET/POST /api/stories/{slug}/sources/ — provenance sources
    """

    lookup_field = 'slug'

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            permission_classes = [permissions.AllowAny]
        elif self.action in ('create',):
            permission_classes = [permissions.IsAuthenticated, IsContributorOrAbove]
        elif self.action in ('update', 'partial_update', 'destroy'):
            permission_classes = [permissions.IsAuthenticated, IsStoryOwnerOrReadOnly]
        elif self.action in (
            'moderation_queue',
            'moderate',
            'record_consent',
            'consent_queue',
            'verify',
            'verification_queue',
            'verify_source',
        ):
            permission_classes = [IsAdminOrManager]
        elif self.action in ('request_consent',):
            permission_classes = [permissions.IsAuthenticated, IsContributorOrAbove]
        else:
            permission_classes = [permissions.IsAuthenticated]
        return [p() for p in permission_classes]

    def get_queryset(self):
        # One visibility rule, shared with every other surface — see
        # `stories.services.visible_stories`.
        queryset = story_services.visible_stories(self.request.user)

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
        # Increment the view count with an F() expression so the read and the
        # write happen in one statement inside the database. The previous form
        # (`view_count=instance.view_count + 1`) read the value in Python and
        # wrote it back, so two concurrent readers of the same story both read
        # N and both wrote N+1 — one view was silently lost every time, and a
        # deliberate burst of parallel requests could pin the count arbitrarily
        # low. `refresh_from_db` then picks up whatever the atomic update
        # actually committed.
        Story.objects.filter(pk=instance.pk).update(
            view_count=F('view_count') + 1
        )
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
            Story.objects.filter(pk=story.pk).update(
                bookmark_count=Greatest(F('bookmark_count') - 1, 0),
            )
            return Response({'bookmarked': False}, status=status.HTTP_200_OK)
        Story.objects.filter(pk=story.pk).update(bookmark_count=F('bookmark_count') + 1)
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
            Story.objects.filter(pk=story.pk).update(
                like_count=Greatest(F('like_count') - 1, 0),
            )
            return Response({'liked': False}, status=status.HTTP_200_OK)
        Story.objects.filter(pk=story.pk).update(like_count=F('like_count') + 1)
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
        """GET /api/stories/moderation_queue/ — unresolved flagged stories.

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
            resolution: optional StoryFlag.Resolution value recording *what
                was done* — corrected, hidden, dismissed, restored. Defaults
                from `action` when omitted, so existing clients keep working.
        """
        story = self.get_object()
        action = request.data.get('action', '')
        notes = request.data.get('notes', '')

        if action not in ('remove', 'dismiss'):
            return Response(
                {'error': 'action must be "remove" or "dismiss"'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        resolution = request.data.get('resolution') or (
            StoryFlag.Resolution.HIDDEN if action == 'remove'
            else StoryFlag.Resolution.DISMISSED
        )
        if resolution not in StoryFlag.Resolution.values:
            return Response(
                {'error': 'resolution must be one of: ' + ', '.join(StoryFlag.Resolution.values)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Resolve every open flag on the story, attributable to the moderator.
        StoryFlag.objects.filter(story=story, resolved=False).update(
            resolved=True,
            resolution_notes=notes,
            resolution_action=resolution,
            resolved_by=request.user,
            resolved_at=timezone.now(),
        )

        before = story.status
        if action == 'remove':
            story.status = Story.Status.ARCHIVED
            story.reviewer_notes = notes
            story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])

        story_services.log_moderation(
            request.user, story, ModerationLog.Action.FLAGS_RESOLVED,
            notes=notes, from_status=before, to_status=story.status,
        )

        return Response({
            'story_id': story.id,
            'slug': story.slug,
            'status': story.status,
            'action': action,
            'resolution': resolution,
            'resolved_flags': StoryFlag.objects.filter(
                story=story, resolved=True,
            ).count(),
        })

    @action(detail=False, methods=['get'])
    def verification_queue(self, request):
        """GET /api/stories/verification_queue/ — stories awaiting review.

        Every row carries what a reviewer needs to decide: the provenance
        the contributor declared, the sources attached, and the evidence
        checklist with the score it currently produces.
        """
        entries = []
        for story in story_services.verification_queue():
            verification = getattr(story, 'verification', None)
            evidence = verification or {
                'source_verified': False,
                'community_validated': False,
                'expert_validated': False,
                'references_confirmed': False,
                'consistency_confirmed': False,
            }
            score = verification.trust_score if verification else 0
            entries.append({
                'story_id': story.id,
                'slug': story.slug,
                'title': story.title,
                'summary': story.summary,
                'status': story.status,
                'author_username': story.author.username,
                'origin': story.origin,
                'provenance_notes': story.provenance_notes,
                'consent_status': story.consent_status,
                'language': story.language,
                'region': story.region,
                'created_at': story.created_at.isoformat(),
                'sources': StorySourceSerializer(
                    story.sources.all(), many=True,
                ).data,
                'trust_score': score,
                'trust_level': trust_level(score),
                'breakdown': score_breakdown(evidence),
                'reviewer': (
                    verification.reviewer.username
                    if verification and verification.reviewer else None
                ),
                'verified_at': (
                    verification.verified_at.isoformat()
                    if verification and verification.verified_at else None
                ),
            })
        return Response(entries)

    @action(detail=True, methods=['post'])
    def verify(self, request, slug=None):
        """POST /api/stories/{slug}/verify/ — record a verification decision.

        Body:
            action:   'start_review' | 'approve' | 'reject' | 'request_changes'
            notes:    optional reviewer notes (appended to reviewer_notes)
            evidence: optional dict of trust criteria —
                source_verified, community_validated, expert_validated,
                references_confirmed, consistency_confirmed

        The trust score is recomputed from the evidence before the decision
        lands, so the score shown beside "Approved" is the score the
        approval was based on.
        """
        story = self.get_object()
        serializer = StoryVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            story, verification = story_services.verify_story(
                request.user,
                story,
                action=serializer.validated_data['action'],
                notes=serializer.validated_data.get('notes', ''),
                evidence=serializer.validated_data.get('evidence'),
            )
        except DjangoValidationError as exc:
            return Response(
                {'error': exc.message_dict},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response({
            'slug': story.slug,
            'status': story.status,
            'trust_score': verification.trust_score,
            'trust_level': trust_level(verification.trust_score),
            'breakdown': score_breakdown(verification),
            'consent_status': story.consent_status,
        })

    @action(detail=True, methods=['post'])
    def verify_source(self, request, slug=None):
        """POST /api/stories/{slug}/verify_source/ — confirm a source.

        Body:
            source_id:   the StorySource to update
            is_verified: bool (default true)

        Confirms one checked source and moves the first trust criterion
        with it: a story counts as source-verified the moment at least one
        of its sources has been checked.
        """
        story = self.get_object()
        source_id = request.data.get('source_id')
        try:
            source = story.sources.get(pk=source_id)
        except (StorySource.DoesNotExist, TypeError, ValueError):
            return Response(
                {'error': 'source_id must reference a source of this story.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        is_verified = request.data.get('is_verified', True)
        story_services.verify_source(
            request.user, source, is_verified=bool(is_verified),
        )
        # Re-read rather than trusting `story`'s prefetch cache: the service
        # may have just created or updated the evidence row.
        verification = StoryVerification.objects.filter(story=story).first()
        return Response({
            'source': StorySourceSerializer(source).data,
            'trust_score': verification.trust_score if verification else 0,
            'trust_level': trust_level(verification.trust_score if verification else 0),
        })

    @action(detail=False, methods=['get'])
    def consent_queue(self, request):
        """GET /api/stories/consent_queue/ — stories awaiting a consent decision.

        The moderator worklist, and the surface the Flutter and web consent
        forms hang off. Everything needed to *make* the decision travels with
        the row — what the contributor declared about the text, who holds the
        rights, which licence it currently carries — because a consent status
        recorded without them is a claim rather than a record. See
        `stories.services.consent_review_queue` for what "awaiting" means.
        """
        return Response([
            {
                'story_id': story.id,
                'slug': story.slug,
                'title': story.title,
                'summary': story.summary,
                'status': story.status,
                'author_username': story.author.username,
                'origin': story.origin,
                'provenance_notes': story.provenance_notes,
                'consent_status': story.consent_status,
                'consent_basis': story.consent_basis,
                'rights_holder': story.rights_holder,
                'licence': story.licence,
                'language': story.language,
                'region': story.region,
                'created_at': story.created_at.isoformat(),
                'consent_attested_by': (
                    story.consent_attested_by.username
                    if story.consent_attested_by else None
                ),
                'consent_attested_at': (
                    story.consent_attested_at.isoformat()
                    if story.consent_attested_at else None
                ),
            }
            for story in story_services.consent_review_queue()
        ])

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated, IsContributorOrAbove])
    def request_consent(self, request, slug=None):
        """POST /api/stories/{slug}/request_consent/ — consent has been *asked for*.

        Moves `not_requested` -> `pending`. The contributor records that they
        asked; only a moderator records what the community answered, at
        `.../record_consent/`. Idempotent: asking twice changes nothing.
        """
        story = story_services.request_consent(request.user, self.get_object())
        return Response({
            'slug': story.slug,
            'consent_status': story.consent_status,
        })

    @action(detail=True, methods=['post'])
    def record_consent(self, request, slug=None):
        """POST /api/stories/{slug}/record_consent/ — record the community's answer.

        Body:
            status:         one of Story.Consent
            basis:          required — on what basis the decision was made
            rights_holder:  optional override
            licence:        optional override

        Also stamps `consent_attested_by`, `consent_attested_at` and
        `consent_basis`, because a status with no name and date behind it
        cannot answer "says who". Withdrawing consent on a published story
        archives it rather than failing — see `stories.services.record_consent`.
        """
        try:
            story, archived = story_services.record_consent(
                request.user,
                self.get_object(),
                status=request.data.get('status', ''),
                basis=request.data.get('basis', ''),
                rights_holder=request.data.get('rights_holder'),
                licence=request.data.get('licence'),
            )
        except DjangoValidationError as exc:
            return Response(
                {'error': exc.message_dict},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response({
            'slug': story.slug,
            'status': story.status,
            'consent_status': story.consent_status,
            'consent_basis': story.consent_basis,
            'consent_attested_by': (
                story.consent_attested_by.username
                if story.consent_attested_by else None
            ),
            'consent_attested_at': (
                story.consent_attested_at.isoformat()
                if story.consent_attested_at else None
            ),
            'rights_holder': story.rights_holder,
            'licence': story.licence,
            'archived': archived,
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
        return get_client_ip(request)


# ---------------------------------------------------------------------------
# Story sources (provenance) — /api/stories/{slug}/sources/
# ---------------------------------------------------------------------------
class StorySourceListCreateView(generics.ListCreateAPIView):
    """GET — the documented sources behind a visible story.
    POST — attach a source (author or moderator).

    Reading follows the same visibility rule as the story itself: a source
    for a draft is not public just because its URL was guessed. Writing goes
    through `stories.services.add_source`, which decides ownership.
    """

    serializer_class = StorySourceSerializer
    pagination_class = None  # a story has a handful of sources, not a feed

    def get_permissions(self):
        if self.request.method in permissions.SAFE_METHODS:
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated(), IsContributorOrAbove()]

    def _get_story(self):
        return get_object_or_404(
            story_services.visible_stories(self.request.user),
            slug=self.kwargs['slug'],
        )

    def get_queryset(self):
        return self._get_story().sources.all()

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        story = self._get_story()
        try:
            source = story_services.add_source(
                request.user, story, **serializer.validated_data,
            )
        except DjangoValidationError as exc:
            return Response(
                {'error': exc.message_dict},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            StorySourceSerializer(source).data,
            status=status.HTTP_201_CREATED,
        )


class StorySourceDetailView(generics.RetrieveUpdateDestroyAPIView):
    """PATCH — the author or a moderator corrects a source record.
    DELETE — the author or a moderator withdraws a source.

    `is_verified` is deliberately not writable here: confirming a source is
    a moderation act with an audit trail (`POST .../verify_source/`), not a
    field the owner flips on their own evidence.
    """

    serializer_class = StorySourceSerializer
    queryset = StorySource.objects.all()

    def get_permissions(self):
        if self.request.method in permissions.SAFE_METHODS:
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated()]

    def get_object(self):
        story = get_object_or_404(
            story_services.visible_stories(self.request.user),
            slug=self.kwargs['slug'],
        )
        obj = get_object_or_404(StorySource, pk=self.kwargs['pk'], story=story)
        self.check_object_permissions(self.request, obj)
        return obj

    def perform_update(self, serializer):
        source = serializer.instance
        user = self.request.user
        if source.story.author_id != user.id and not story_services.is_moderator(user):
            raise DjangoPermissionDenied('You can only edit your own story sources.')
        serializer.save()

    def perform_destroy(self, instance):
        user = self.request.user
        if instance.story.author_id != user.id and not story_services.is_moderator(user):
            raise DjangoPermissionDenied('You can only remove your own story sources.')
        instance.delete()


# ---------------------------------------------------------------------------
# Category List (standalone endpoint)
# ---------------------------------------------------------------------------
class StoryCategoryListView(generics.ListAPIView):
    """GET /api/stories/categories/ — list all story categories."""

    queryset = StoryCategory.objects.all()
    serializer_class = StoryCategorySerializer
    permission_classes = [permissions.AllowAny]