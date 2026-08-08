"""Custom middleware for the Griot 2.0 backend (Phase 10)."""

import logging
import time

logger = logging.getLogger('api.request')

# In-process counters exposed by the /api/health/metrics/ endpoint.
# Note: these are per-process; aggregate across replicas with a real
# metrics pipeline (e.g. Prometheus) for production.
requests_served = 0
_startup_time = time.time()


def startup_time() -> float:
    """Wall-clock timestamp of when this worker process started."""
    return _startup_time


def _resolve_username(request):
    """Best-effort username for the request log line.

    DRF's JWT authentication runs inside the view layer, so ``request.user``
    is still anonymous when middleware sees the request. The username is
    therefore extracted from the JWT access token (signature verified, no DB
    hit); session-authenticated requests (e.g. Django admin) fall back to
    ``request.user``.
    """
    user = getattr(request, 'user', None)
    if user and getattr(user, 'is_authenticated', False):
        return user.username

    auth = request.META.get('HTTP_AUTHORIZATION', '')
    if auth.startswith('Bearer '):
        try:
            from rest_framework_simplejwt.tokens import AccessToken
            token = AccessToken(auth[7:])
            return token.get('username')
        except Exception:  # noqa: BLE001 - invalid/expired token: leave unset
            return None
    return None


class RequestLogMiddleware:
    """Emit one structured log line per HTTP request.

    Uses the default Django authentication middleware ordering; the JWT
    username is resolved from the Authorization header (see _resolve_username)
    so the primary API auth method is attributed correctly.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        global requests_served
        start = time.perf_counter()

        response = self.get_response(request)

        duration_ms = (time.perf_counter() - start) * 1000

        logger.info(
            'http_request',
            extra={
                'method': request.method,
                'path': request.path,
                'status': response.status_code,
                'duration_ms': round(duration_ms, 2),
                'user': _resolve_username(request),
                'ip': request.META.get('REMOTE_ADDR'),
            },
        )
        requests_served += 1
        return response
