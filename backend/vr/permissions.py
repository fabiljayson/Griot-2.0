"""Permissions for VR endpoints.

`IsVRSessionToken` exists so that a token minted for a headset is not
interchangeable with a normal account token on these endpoints, and — just as
importantly — so the scope claim is *checked* rather than merely set. A claim
nothing reads is documentation, not security.
"""

from rest_framework.permissions import BasePermission

from .services.session_tokens import VR_TOKEN_SCOPE


class IsVRSessionToken(BasePermission):
    """Require a token minted by the launch exchange."""

    message = 'This endpoint needs an active VR session. Relaunch from the app.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        token = request.auth
        if token is None:
            return False

        # `request.auth` is a SimpleJWT `Token` (mapping-like) for JWT auth and
        # something else entirely for session auth, so `get` is not assumed.
        getter = getattr(token, 'get', None)
        if getter is None:
            return False

        return getter('scope') == VR_TOKEN_SCOPE


class IsAuthenticatedForVR(BasePermission):
    """Any valid token — a reader's own JWT or a VR session token.

    Used for the read endpoints Unity hits after the exchange. It deliberately
    does not require the VR scope: these payloads are the same public artifact
    and story data the website serves, so refusing a reader's own token would
    add friction without protecting anything.
    """

    message = 'Authentication is required.'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated)
