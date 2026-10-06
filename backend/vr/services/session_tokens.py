"""Mint the short-lived, VR-scoped JWT Unity uses after the exchange.

Design notes, because this is the part a reviewer will ask about:

* **No refresh token.** The phone holds the refresh token and keeps it there.
  Handing one to a headset would mean a device that can extend its own access
  indefinitely, and the whole point of the launch token is that VR access is
  bounded.
* **`scope: vr`.** A plain access token would be a full account token: leaked
  from a headset, it reads and writes every story, bookmark and profile the
  reader owns. The scope claim plus `IsVRSessionToken` keeps VR endpoints
  accessible and everything else out, and the short lifetime bounds the damage
  if it does leak.
* **`sid`** binds the token to one session, which is what makes
  `complete` idempotent and lets reconnects resume the same row.

This is still a `rest_framework_simplejwt` token: it validates with the project's
existing `JWTAuthentication`, so no second authentication mechanism exists that
could drift from the first.
"""

from datetime import timedelta

from django.conf import settings
from rest_framework_simplejwt.tokens import AccessToken

#: Value of the `scope` claim on every VR session token.
VR_TOKEN_SCOPE = 'vr'


def vr_session_token_minutes() -> int:
    return int(getattr(settings, 'VR_SESSION_TOKEN_MINUTES', 45))


def mint_session_token(*, user, session) -> tuple[str, int]:
    """Return `(encoded_token, lifetime_seconds)` for `session`."""
    lifetime = timedelta(minutes=vr_session_token_minutes())

    token = AccessToken.for_user(user)
    token['scope'] = VR_TOKEN_SCOPE
    token['sid'] = session.pk
    token['experience'] = session.experience_id
    # Resets both `iat` and `exp`; called last so the lifetime covers the claims
    # written above rather than the (longer) default access-token window.
    token.set_exp(lifetime=lifetime)

    return str(token), int(lifetime.total_seconds())
