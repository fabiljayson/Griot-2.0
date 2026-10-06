"""Issue and consume short-lived VR launch tokens.

The token is the only thing that crosses the Android deep-link boundary, so
everything about it is designed for the case where the link is read or replayed
by someone else:

  * 32 bytes of `secrets` entropy, URL-safe encoded (43 characters);
  * the database stores a SHA-256 digest, so a dump yields no usable token;
  * a short TTL (`VR_LAUNCH_TOKEN_TTL_SECONDS`, default 120 s);
  * single use, claimed with an atomic conditional UPDATE so two racing
    exchanges cannot both win;
  * bound to the user and the experience that requested it.

Nothing else travels in the URI. In particular no password, no refresh token,
no API key and no user identifier — Unity learns who the reader is only after
it has exchanged the token with the server.
"""

import hashlib
import secrets
from dataclasses import dataclass
from datetime import timedelta
from urllib.parse import urlencode

from django.conf import settings
from django.db import connection, transaction
from django.utils import timezone

from ..models import VRLaunchToken

#: Bytes of entropy in a launch token. 32 bytes → 43 URL-safe characters.
TOKEN_BYTES = 32

#: Refuse absurd inputs before touching the database. The longest legitimate
#: token is 43 characters; anything far past that is an attack or a bug.
MAX_TOKEN_LENGTH = 200


class LaunchTokenError(Exception):
    """Base class for launch-token failures.

    Each subclass maps to a distinct HTTP status and a distinct machine-readable
    `code`, because Unity's user-facing message differs per case: a used link
    says "this link has already been used, tap Explore in VR again", which is
    useless advice for an expired one.
    """

    code = 'invalid_token'


class InvalidLaunchToken(LaunchTokenError):
    """Malformed, unknown, or tampered token."""

    code = 'invalid_token'


class ExpiredLaunchToken(LaunchTokenError):
    """Known token whose TTL has passed."""

    code = 'token_expired'


class UsedLaunchToken(LaunchTokenError):
    """Known token that has already been exchanged."""

    code = 'token_used'


@dataclass(frozen=True)
class IssuedLaunchToken:
    """The plaintext token plus what the caller needs to describe it.

    The plaintext exists only in this object and in the HTTP response. It is
    never logged and never persisted.
    """

    token: str
    expires_at: object
    ttl_seconds: int

    @property
    def expires_in(self) -> int:
        """Whole seconds until expiry, never negative."""
        remaining = (self.expires_at - timezone.now()).total_seconds()
        return max(0, int(remaining))


def hash_token(token: str) -> str:
    """SHA-256 hex digest of `token`.

    A plain hash, not a password hash: this is a 256-bit random value with no
    guessable structure, so there is nothing to slow down and the exchange path
    must stay cheap enough to run on every VR launch.
    """
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def launch_token_ttl() -> int:
    return int(getattr(settings, 'VR_LAUNCH_TOKEN_TTL_SECONDS', 120))


def issue_launch_token(*, user, experience, artifact=None, ttl_seconds=None):
    """Create and return a fresh launch token for `user` and `experience`."""
    ttl = int(ttl_seconds or launch_token_ttl())
    token = secrets.token_urlsafe(TOKEN_BYTES)
    expires_at = timezone.now() + timedelta(seconds=ttl)

    VRLaunchToken.objects.create(
        user=user,
        experience=experience,
        artifact=artifact,
        token_hash=hash_token(token),
        expires_at=expires_at,
    )

    return IssuedLaunchToken(token=token, expires_at=expires_at, ttl_seconds=ttl)


def consume_launch_token(*, token: str) -> VRLaunchToken:
    """Validate and burn `token`, returning the row it belonged to.

    Raises `InvalidLaunchToken`, `ExpiredLaunchToken` or `UsedLaunchToken`.

    The claim is a conditional `UPDATE ... WHERE used_at IS NULL`, whose
    affected-row count is the decision. That is atomic on every backend the
    project targets, which `select_for_update()` is not — SQLite ignores it —
    and it is the check that actually stops a replay when two Unity instances
    receive the same link.
    """
    if not token or len(token) > MAX_TOKEN_LENGTH:
        raise InvalidLaunchToken('That VR link is not valid.')

    token_hash = hash_token(token)

    with transaction.atomic():
        queryset = VRLaunchToken.objects.filter(token_hash=token_hash)
        if connection.features.has_select_for_update:
            # Postgres: take the row lock too, so the read and the claim below
            # cannot interleave with a concurrent exchange.
            queryset = queryset.select_for_update()

        row = queryset.first()
        if row is None:
            raise InvalidLaunchToken('That VR link is not valid.')

        now = timezone.now()
        if row.used_at is not None:
            raise UsedLaunchToken('That VR link has already been used.')
        if row.expires_at <= now:
            raise ExpiredLaunchToken('That VR link has expired.')

        claimed = VRLaunchToken.objects.filter(
            pk=row.pk,
            used_at__isnull=True,
            expires_at__gt=now,
        ).update(used_at=now)

        if not claimed:
            # Lost the race with a concurrent exchange between the read and
            # this write. Report it as "used", which is what it now is.
            raise UsedLaunchToken('That VR link has already been used.')

        row.used_at = now

    return row


def build_deep_link(*, token: str, experience, artifact=None) -> str:
    """Build the `griotvr://launch?...` URI Unity receives.

    Built server-side so the scheme lives in exactly one place
    (`VR_DEEP_LINK_SCHEME`) and the link can be asserted on in tests. Flutter
    re-validates and rebuilds it before firing the intent rather than passing
    this string through untouched.
    """
    scheme = getattr(settings, 'VR_DEEP_LINK_SCHEME', 'griotvr')
    host = getattr(settings, 'VR_DEEP_LINK_HOST', 'launch')

    params = {'token': token, 'experience': str(experience.pk)}
    if artifact is not None:
        params['artifact'] = str(artifact.pk)

    return f'{scheme}://{host}?{urlencode(params)}'
