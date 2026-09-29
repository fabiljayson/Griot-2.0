import time

from django.contrib.auth import get_user_model
from django.db import connection
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle

from gamification.models import QuizAttempt, UserBadge
from qr_codes.models import Artifact, QRCodeScan
from stories.models import Story

from .middleware import requests_served, startup_time

User = get_user_model()


class MetricsThrottle(AnonRateThrottle):
    """Tighter rate for the unauthenticated metrics endpoint.

    Six `count()` queries per anonymous request is a useful load generator, so
    this sits well below the general `anon` budget while still leaving room for
    a 15-second polling monitor.
    """

    scope = 'metrics'


def _banded_count(value: int) -> int:
    """Round [value] up to the next power of two.

    Rounding up keeps the response an upper bound (never under-reports, which
    would let a caller recover the true total by arithmetic) while hiding the
    exact figure. Returns 0 for 0 so an empty instance does not claim to hold
    one record.
    """
    if value <= 0:
        return 0
    return 1 << (value - 1).bit_length()


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """Liveness probe used by the Flutter client and uptime monitors."""
    return Response({
        'status': 'ok',
        'service': 'griot-2.0-backend',
        'version': '0.1.0',
    })


@api_view(['GET'])
@permission_classes([AllowAny])
def health_ready(request):
    """Readiness probe: verifies the database is reachable.

    Returns 200 when the service can serve traffic and 503 otherwise, so
    orchestrators can route traffic away from unhealthy instances.
    """
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()
        database = 'ok'
    except Exception:  # noqa: BLE001 - any DB failure means not ready
        database = 'error'

    ready = database == 'ok'
    return Response(
        {'status': 'ok' if ready else 'degraded', 'database': database},
        status=status.HTTP_200_OK if ready else status.HTTP_503_SERVICE_UNAVAILABLE,
    )


@api_view(['GET'])
@permission_classes([AllowAny])
@throttle_classes([MetricsThrottle])
def health_metrics(request):
    """Lightweight application metrics for monitoring.

    ## Why these counts are banded

    The endpoint is unauthenticated — load balancers and uptime monitors have
    no credentials — but the previous version returned *exact* record counts
    (`users: 4821`, `qr_scans: 19043`). That is a business-information
    disclosure to an anonymous caller: exact totals combined with the public
    story and artifact lists reveal sign-up growth, total scan volume, and —
    because `published_stories` is public while `users` is not — a fairly tight
    bound on unpublished content and on how many accounts exist at all. It also
    makes the endpoint an unauthenticated counting oracle: `count()` on six
    tables per request is a cheap way to pin a Postgres instance.

    Each value is now rounded **up** to the next power of two, which is the
    standard technique for cardinality hiding: a monitoring system still sees
    the right order of magnitude and can alert on the bands, while an attacker
    cannot tell 4821 from 4822, and cannot count by differencing successive
    reads. Rounding up (never down) is deliberate — rounding down would let a
    caller subtract the under-report from the real number over enough samples.

    Process gauges are per-worker; aggregate across replicas with a real
    metrics pipeline (e.g. Prometheus) for production dashboards.
    """
    uptime = time.time() - startup_time()
    return Response({
        'process': {
            'uptime_seconds': round(uptime, 1),
            'requests_served': requests_served,
        },
        'counts': {
            'users': _banded_count(User.objects.count()),
            'published_stories': _banded_count(
                Story.objects.filter(status=Story.Status.PUBLISHED).count()
            ),
            'artifacts': _banded_count(Artifact.objects.count()),
            'qr_scans': _banded_count(QRCodeScan.objects.count()),
            'quiz_attempts': _banded_count(QuizAttempt.objects.count()),
            'badges_earned': _banded_count(UserBadge.objects.count()),
        },
    })
