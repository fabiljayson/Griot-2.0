"""
Fixed-window rate limiting for the server-rendered web views.

DRF throttles (``REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']``) only apply to
DRF views. The web interface is plain Django functions, so the ``auth: 5/min``
budget that protects the API did not protect ``accounts/login/`` or
``accounts/register/``, leaving them open to unlimited online password
guessing. This decorator applies the same idea to a normal view function.

Backed by Django's default cache. That is the same store the DRF throttles
already use, so this introduces no new infrastructure — and the same caveat
applies to both: with no ``CACHES`` configured the default is a per-process
``LocMemCache``, so under ``gunicorn --workers N`` the effective allowance is
N times the configured limit. Configure a shared cache (Redis/Memcached) for an
exact global limit.
"""

import functools

from django.conf import settings
from django.core.cache import cache
from django.http import HttpResponse

from config.client_ip import get_client_ip

DEFAULT_WINDOW_SECONDS = 60


def client_identifier(request, key_by: str = 'auto') -> str:
    """A client key that an attacker cannot forge.

    ``key_by='auto'`` (the default) prefers the authenticated user, so a
    logged-in caller is limited per account rather than per shared NAT address,
    and falls back to a trust-aware IP (only honours ``X-Forwarded-For``
    behind a trusted proxy). Anonymous callers all share ``ip:unknown`` when
    no IP can be resolved, which still caps them collectively rather than
    not at all.

    ``key_by='ip'`` forces the IP key even when authenticated. Required for
    registration: a successful signup logs the caller in, so an ``'auto'`` key
    would rotate to the freshly minted user's primary key on every attempt and
    hand each one a brand-new budget — the throttle would never fire.
    """
    if key_by == 'ip':
        return f'ip:{get_client_ip(request) or "unknown"}'
    user = getattr(request, 'user', None)
    if user is not None and getattr(user, 'is_authenticated', False):
        return f'user:{user.pk}'
    return f'ip:{get_client_ip(request) or "unknown"}'


def first_in_window(scope: str, identity: str, window: int) -> bool:
    """True the *first* time ``identity`` is seen within ``window`` seconds.

    Records the sighting on the first call, then returns False until the key
    expires. This is for collapsing duplicate *analytics* writes that a read
    endpoint triggers as a side effect (e.g. an artifact view scan): a viewer
    reloading or a bot crawling the same artifact should not create a row per
    request, and the real signal is "was this artifact viewed", not "how many
    HTTP requests arrived". Lossy by design — do not use it to gate work that
    must happen exactly once.
    """
    key = f'window:{scope}:{identity}'
    if cache.get(key):
        return False
    cache.set(key, 1, window)
    return True


def _consume(key: str, window: int) -> int:
    """Increment ``key`` and return the running count for this window."""
    count = cache.get(key)
    if count is None:
        cache.set(key, 1, window)
        return 1
    try:
        return cache.incr(key)
    except ValueError:  # key expired between get and incr
        cache.set(key, 1, window)
        return 1


def rate_limit(
    scope: str,
    limit=None,
    window: int = DEFAULT_WINDOW_SECONDS,
    methods: tuple | None = None,
    key_by: str = 'auto',
):
    """Limit a view to ``limit`` calls per ``window`` seconds per client.

    Exceeding the limit returns ``429 Too Many Requests`` with a ``Retry-After``
    header instead of running the view. ``limit`` defaults to the shared
    ``WEB_AUTH_ATTEMPTS_PER_MIN`` setting (mirroring the API's ``auth: 5/min``)
    so the web and API budgets stay tunable from one place.

    ``methods`` restricts which HTTP methods consume budget. Auth screens serve
    an unauthenticated GET form *and* accept the POST attempt; only the POST
    should count, otherwise simply loading the login page would burn the
    caller's allowance. ``None`` (the default) counts every method.
    """
    def decorator(view_func):
        @functools.wraps(view_func)
        def wrapper(request, *args, **kwargs):
            # Resolve the limit per request, not at import time, so a settings
            # override (tests, env-driven config) takes effect immediately and
            # the value is never frozen when this module is first imported.
            effective = limit if limit is not None else getattr(
                settings, 'WEB_AUTH_ATTEMPTS_PER_MIN', 5
            )
            counts = methods is None or request.method in methods
            if effective and counts:
                key = f'ratelimit:{scope}:{client_identifier(request, key_by)}'
                count = _consume(key, window)
                if count > effective:
                    response = HttpResponse(
                        'Too many requests. Please try again shortly.',
                        status=429,
                    )
                    response['Retry-After'] = str(window)
                    return response
            return view_func(request, *args, **kwargs)

        return wrapper

    return decorator


def reset_client_budget(scope: str, request) -> None:
    """Clear a client's budget for ``scope`` — call after a *successful* auth
    attempt so a legitimate user who mistyped once is not penalised.

    Appropriate for login, NOT for registration. A successful registration is
    exactly what the register throttle exists to bound, so clearing the budget
    on success would let a caller create unlimited accounts (each success
    resets the counter) and silently defeat the control.
    """
    cache.delete(f'ratelimit:{scope}:{client_identifier(request)}')


__all__ = [
    'rate_limit',
    'reset_client_budget',
    'client_identifier',
    'first_in_window',
    'DEFAULT_WINDOW_SECONDS',
]
