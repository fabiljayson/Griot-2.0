import time

from django.contrib.auth import get_user_model
from django.db import connection
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from gamification.models import QuizAttempt, UserBadge
from qr_codes.models import Artifact, QRCodeScan
from stories.models import Story

from .middleware import requests_served, startup_time

User = get_user_model()


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
def health_metrics(request):
    """Lightweight application metrics for monitoring.

    Intentionally unauthenticated (load balancers and uptime monitors need
    it) and exposes aggregate record counts only — never individual records
    or user data. Process gauges are per-worker; aggregate across replicas
    with a real metrics pipeline (e.g. Prometheus) for production dashboards.
    """
    uptime = time.time() - startup_time()
    return Response({
        'process': {
            'uptime_seconds': round(uptime, 1),
            'requests_served': requests_served,
        },
        'counts': {
            'users': User.objects.count(),
            'published_stories': Story.objects.filter(
                status=Story.Status.PUBLISHED,
            ).count(),
            'artifacts': Artifact.objects.count(),
            'qr_scans': QRCodeScan.objects.count(),
            'quiz_attempts': QuizAttempt.objects.count(),
            'badges_earned': UserBadge.objects.count(),
        },
    })
