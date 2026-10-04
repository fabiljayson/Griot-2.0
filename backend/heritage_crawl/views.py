"""
Administrative API for the crawler (§18).

    POST /api/crawler/start/                run a crawl of one enabled source
    GET  /api/crawler/sources/              configured sources
    GET  /api/crawler/jobs/                 run history
    GET  /api/crawler/jobs/<id>/            one run + its summary
    GET  /api/crawler/items/                the review queue
    GET  /api/crawler/items/<id>/           extraction, provenance, media
    POST /api/crawler/items/<id>/approve/   publish
    POST /api/crawler/items/<id>/reject/    reject, keeping the trail
    POST /api/crawler/items/<id>/correct/   send back for correction

Every view requires `IsAdminOrManager`, mirroring `api.views_analytics`. §19 is
the reason this app has no public read surface at all: Flutter must only ever
receive content that passed review, so there is no "browse crawled items"
endpoint. The queue is an admin screen, not a feature.

Two choices worth calling out:

* **`start` takes a slug, not a URL.** See `CrawlStartSerializer`. §20 rules out
  an unrestricted URL-fetching endpoint; a slug can only resolve to a source
  whose domain allow-list an administrator already set.

* **`start` runs synchronously and says so.** A crawl of 25 pages at a 3s
  polite delay is a ~75-second request. Blocking is wrong in production, but
  queueing introduces infrastructure this project does not have (no Celery, no
  worker), and §11 says do not add what is not needed. So the endpoint is
  synchronous, capped hard by `max_pages`, and the response tells the caller
  what it cost — and the *management command* is the supported way to run
  anything long, where it can run in the background outside a request cycle.
"""

import logging

from django.http import Http404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from .ingest import crawl_source
from .models import CrawledItem, CrawlJob, CrawlSource
from .review import ReviewError, approve_item, reject, request_correction, unpublish
from .serializers import (
    CrawledItemSerializer,
    CrawlJobSerializer,
    CrawlSourceSerializer,
    CrawlStartSerializer,
    ReviewActionSerializer,
)

log = logging.getLogger('heritage_crawl.api')


class IsAdminOrManager(BasePermission):
    """Crawler administration is admin-only.

    Mirrors `api.views_analytics.IsAdminOrManager`. `institution_manager` is
    included because §13 says "an administrator or authorized cultural
    contributor" may approve; a curator role already exists in this project and
    re-deriving it here would create two definitions of who may curate.
    """

    message = 'Crawler administration requires administrator or manager role.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in ('admin', 'institution_manager')


def _flagged(item: CrawledItem, reviewer, reason: str) -> None:
    """Record who decided what, on the Story that a reader will eventually see.

    The reviewer's note is written even for a rejection, because a story that was
    rejected is still in the database and whoever opens it next needs to know it
    was looked at and turned down, rather than simply missed.
    """
    from django.utils import timezone

    stamp = timezone.now().strftime('%Y-%m-%d %H:%M')
    who = getattr(reviewer, 'username', 'system')
    text = f'[{stamp}] {who}: {reason or "no reason given"}'
    if item.story_id:
        item.story.reviewer_notes = text
        item.story.save(update_fields=['reviewer_notes', 'updated_at'])
    elif item.artifact_id:
        log.info('review note for artifact %s: %s', item.artifact_id, text)


class CrawlStartView(APIView):
    """POST /api/crawler/start/ — run one crawl synchronously."""

    permission_classes = [IsAdminOrManager]
    # Named so drf-spectacular can document the request body. Without it the
    # endpoint is omitted from the OpenAPI schema entirely (§18 asks for these
    # endpoints to be part of the documented API surface).
    serializer_class = CrawlStartSerializer

    def post(self, request):
        serializer = CrawlStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        slug = serializer.validated_data['source']
        try:
            source = CrawlSource.objects.get(slug=slug)
        except CrawlSource.DoesNotExist:
            return Response(
                {'detail': f'No crawl source with slug {slug!r}.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not source.enabled:
            # Not a 403: nothing is wrong with the caller, the source simply
            # is not switched on. Enabling is an admin decision.
            return Response(
                {
                    'detail': f'Source {slug!r} is disabled. Enable it in the '
                              'admin before crawling.'
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            outcome = crawl_source(
                source,
                triggered_by=request.user,
                max_pages=serializer.validated_data.get('max_pages'),
                store_full_text=serializer.validated_data.get('store_full_text'),
            )
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(
            {
                'job': CrawlJobSerializer(outcome.job).data,
                'imported': outcome.imported,
                'duplicates': outcome.duplicates,
                'skipped': outcome.skipped,
                'errors': outcome.errors,
                'media_recorded': outcome.media_recorded,
                'item_ids': outcome.item_ids,
            },
            status=status.HTTP_201_CREATED,
        )


class CrawlSourceViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/crawler/sources/ — what may be crawled, and by whom."""

    queryset = CrawlSource.objects.all()
    serializer_class = CrawlSourceSerializer
    permission_classes = [IsAdminOrManager]
    pagination_class = None


class CrawlJobViewSet(viewsets.ReadOnlyModelViewSet):
    """GET /api/crawler/jobs/ — run history (§16)."""

    queryset = CrawlJob.objects.select_related('source', 'triggered_by')
    serializer_class = CrawlJobSerializer
    permission_classes = [IsAdminOrManager]

    def get_queryset(self):
        qs = super().get_queryset()
        source_slug = self.request.query_params.get('source')
        if source_slug:
            qs = qs.filter(source__slug=source_slug)
        status_param = self.request.query_params.get('status')
        if status_param:
            qs = qs.filter(status=status_param)
        return qs


class CrawledItemViewSet(viewsets.ReadOnlyModelViewSet):
    """The review queue plus its three actions."""

    queryset = CrawledItem.objects.select_related(
        'source', 'job', 'story', 'artifact'
    ).prefetch_related('references', 'media')
    serializer_class = CrawledItemSerializer
    permission_classes = [IsAdminOrManager]

    def get_queryset(self):
        """Filterable by state, since "what needs reviewing" is the real query.

        Defaults to the reviewable states rather than everything: an
        administrator opening this endpoint wants the queue, and a page
        dominated by error rows is a queue nobody reads.
        """
        qs = super().get_queryset()
        state = self.request.query_params.get('status')
        if state:
            qs = qs.filter(processing_status=state)
        elif not self.request.query_params.get('all'):
            qs = qs.filter(
                processing_status__in=[
                    CrawledItem.ProcessingStatus.IMPORTED,
                    CrawledItem.ProcessingStatus.NEEDS_CORRECTION,
                ]
            )
        source_slug = self.request.query_params.get('source')
        if source_slug:
            qs = qs.filter(source__slug=source_slug)
        return qs

    def _item(self, pk) -> CrawledItem:
        try:
            return self.get_queryset().get(pk=pk)
        except CrawledItem.DoesNotExist as exc:
            raise Http404 from exc

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Publish a reviewed item.

        `review.approve_item` raises rather than returning a flag when the item
        is unapprovable, and those refusals are substantive (no provenance, no
        produced content) — so they surface as 409, not a cheerful 200 with a
        false success.
        """
        item = self._item(pk)
        ReviewActionSerializer(data=request.data).is_valid(raise_exception=True)
        try:
            approve_item(item, reviewer=request.user)
        except ReviewError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_409_CONFLICT)
        return Response(self.get_serializer(item).data)

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Reject an item, keeping the provenance record (§13)."""
        item = self._item(pk)
        serializer = ReviewActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data.get('reason', '')

        if not reject(item, reviewer=request.user, reason=reason):
            return Response(
                {
                    'detail': 'Item is not awaiting review; it is '
                              f'{item.get_processing_status_display()}.'
                },
                status=status.HTTP_409_CONFLICT,
            )
        return Response(self.get_serializer(item).data)

    @action(detail=True, methods=['post'], url_path='request-correction')
    def correct(self, request, pk=None):
        """Send an item back for correction, leaving it unpublished."""
        item = self._item(pk)
        serializer = ReviewActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data.get('reason', '')

        if not request_correction(item, reviewer=request.user, reason=reason):
            return Response(
                {
                    'detail': 'Item is not awaiting review; it is '
                              f'{item.get_processing_status_display()}.'
                },
                status=status.HTTP_409_CONFLICT,
            )
        _flagged(item, request.user, f'correction requested: {reason}')
        return Response(self.get_serializer(item).data)

    @action(detail=True, methods=['post'])
    def unpublish(self, request, pk=None):
        """Withdraw approved content, keeping the trail.

        Not in the spec's endpoint list. It is here because §5/§13's promise is
        that provenance survives, and a project that can withdraw content but
        cannot un-withdraw it has no path when a rights holder objects after
        publication.
        """
        item = self._item(pk)
        serializer = ReviewActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data.get('reason', '')

        if not unpublish(item, reviewer=request.user, reason=reason):
            return Response(
                {
                    'detail': 'Only an approved item can be unpublished; this '
                              f'one is {item.get_processing_status_display()}.'
                },
                status=status.HTTP_409_CONFLICT,
            )
        return Response(self.get_serializer(item).data)
