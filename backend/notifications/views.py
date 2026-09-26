from django.utils import timezone
from rest_framework import pagination, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response

from . import services
from .models import Notification
from .serializers import NotificationSerializer


class IsAdmin(BasePermission):
    """Admin-only, for the broadcast route."""

    message = 'Only an administrator can broadcast a notification.'

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == 'admin'
        )


class InboxPagination(pagination.PageNumberPagination):
    """Wider than the API default: an inbox is read in pages of 20-plus, and
    20 messages is barely a screenful of history."""

    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 100


class NotificationViewSet(viewsets.ModelViewSet):
    """The reader's inbox: list, open, and bulk-mark.

    The queryset is scoped to the requesting reader, so every route that resolves
    a ``Notification`` is safe by construction — asking for someone else's id
    gets a 404 rather than their data.
    """

    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = InboxPagination
    # No PUT and no DELETE: the inbox is a log, and a client that can delete or
    # replace a message can also lie about one existing.
    http_method_names = ['get', 'post', 'patch', 'head', 'options']

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)

    def _inbox_payload(self, request):
        """The page of messages plus the badge count in one response.

        The bell badge and the list are always fetched together; returning them
        separately would double the requests on every inbox open.
        """
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        results = self.get_serializer(
            page if page is not None else queryset, many=True
        ).data
        payload = {
            'results': results,
            'unread_count': services.unread_count(request.user),
        }
        if page is not None:
            # PageNumberPagination keeps the total on the page's own
            # Django paginator, not on the DRF paginator.
            payload['count'] = self.paginator.page.paginator.count
            payload['next'] = self.paginator.get_next_link()
            payload['previous'] = self.paginator.get_previous_link()
        return payload

    def list(self, request, *args, **kwargs):
        """GET /api/notifications/ — the inbox, newest first."""
        return Response(self._inbox_payload(request))

    @action(detail=False, methods=['get'], url_path='unread-count')
    def unread_count(self, request):
        """GET /api/notifications/unread-count/ — badge only, cheap poll."""
        return Response({'unread_count': services.unread_count(request.user)})

    @action(detail=True, methods=['post'], url_path='mark-read')
    def mark_read(self, request, pk=None):
        """POST /api/notifications/{id}/mark-read/ — open one message."""
        notification = self.get_object()
        notification.mark_read()
        return Response(self.get_serializer(notification).data)

    @action(detail=False, methods=['post'], url_path='mark-all-read')
    def mark_all_read(self, request):
        """POST /api/notifications/mark-all-read/ — clear the badge."""
        updated = services.mark_all_read(request.user)
        return Response(
            {'marked': updated, 'unread_count': services.unread_count(request.user)}
        )

    @action(
        detail=False,
        methods=['post'],
        url_path='broadcast',
        permission_classes=[IsAdmin],
    )
    def broadcast(self, request):
        """POST /api/notifications/broadcast/ — send an announcement.

        The "updates" channel: an admin posts a message and every active reader
        sees it in their inbox when they next open the app. This is a fan-out
        over every active account, which is why it is admin-only.
        """
        title = (request.data.get('title') or '').strip()
        body = (request.data.get('body') or '').strip()
        if not title:
            return Response(
                {'error': 'title is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        created = services.announce(title[:120], body)
        return Response(
            {'created': created, 'sent_at': timezone.now()},
            status=status.HTTP_201_CREATED,
        )
