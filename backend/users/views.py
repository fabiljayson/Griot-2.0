from django.contrib.auth import get_user_model
from drf_spectacular.utils import (
    OpenApiResponse,
    extend_schema,
    extend_schema_view,
    inline_serializer,
)
from rest_framework import generics, permissions, serializers, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import (
    CustomTokenObtainPairSerializer,
    PrivateUserSerializer,
    RegisterSerializer,
)

User = get_user_model()


# ---------------------------------------------------------------------------
# Auth throttling — strict 5 requests / minute per IP (Task 2.1)
# ---------------------------------------------------------------------------
class AuthRateThrottle(SimpleRateThrottle):
    """Strict 5 requests / minute per IP on every auth endpoint (Task 2.1).

    Rate comes from DEFAULT_THROTTLE_RATES['auth'] = '5/min'.
    """

    scope = 'auth'

    def get_cache_key(self, request, view):
        ident = self.get_ident(request)
        return self.cache_format % {'scope': self.scope, 'ident': ident}


# ---------------------------------------------------------------------------
# Token endpoints
# ---------------------------------------------------------------------------
class CustomTokenObtainPairView(TokenObtainPairView):
    """POST /api/auth/token/ — exchange username/password for JWT pair."""

    serializer_class = CustomTokenObtainPairSerializer
    throttle_classes = [AuthRateThrottle]


class AuthTokenRefreshView(TokenRefreshView):
    """POST /api/auth/token/refresh/ — rotate a refresh token for a new pair."""

    throttle_classes = [AuthRateThrottle]


@extend_schema_view(
    post=extend_schema(
        summary='Blacklist a refresh token',
        description=(
            'Revokes the supplied refresh token server-side. Idempotent: a '
            'missing, malformed, expired or already-blacklisted token all '
            'resolve to the same 204.'
        ),
        request=inline_serializer(
            'LogoutRequest',
            {'refresh': serializers.CharField()},
        ),
        responses={
            204: None,
            400: OpenApiResponse(description='Malformed body.'),
        },
    ),
)
class LogoutView(APIView):
    """POST /api/auth/logout/ — blacklist the reader's refresh token.

    Signing out must revoke the session server-side: a refresh token saved
    in an offline queue, copied off a lost device, or left in a backup of
    this repository keeps minting access tokens for the full
    REFRESH_TOKEN_LIFETIME if it is only cleared client-side.

    Idempotent by design. The body carries the token to revoke (`refresh`);
    a missing, malformed, expired or already-blacklisted token all resolve
    to the same 204 — the client clears local state either way, and a logout
    that 401s would strand the reader in a signed-in UI with dead tokens.

    The refresh token is the credential, so this endpoint carries no
    authentication requirement: requiring a valid access token would make
    logout impossible exactly when it is needed most (expired access token).
    """

    authentication_classes = []
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthRateThrottle]

    def post(self, request):
        refresh = request.data.get('refresh')
        if isinstance(refresh, str) and refresh:
            try:
                # Constructing the token runs its blacklist check as well, so
                # an already-revoked token raises here — exactly the idempotent
                # no-op this endpoint wants.
                RefreshToken(refresh).blacklist()
            except TokenError:
                # Invalid, expired, or already revoked — nothing left to do.
                pass
        return Response(status=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------
class RegisterView(generics.CreateAPIView):
    """POST /api/auth/register/ — create a Visitor or Contributor account.

    The endpoint is idempotent on an exact replay of an already-committed
    registration. The hosted backend sleeps on Render's free tier, so a
    cold-start can push the 201 past the client's timeout; the client then
    re-POSTs the identical body. That replay resolves to HTTP 200 with the
    existing account instead of a misleading 'email already exists' 400. A
    request whose username or password differs is a real conflict and still
    gets the 400.
    """

    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthRateThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        data = request.data

        # The replay lookup runs before `is_valid()` on purpose: the
        # serializer's own `username` uniqueness check would reject the replay
        # of a committed registration with a 400, which is the exact false
        # "email already exists" that the idempotency below exists to avoid.
        # `find_by_email` normalizes defensively, so a JSON body carrying
        # `email` as a list or a number is treated as "no address" and falls
        # through to normal validation instead of raising.
        existing = serializer.find_by_email(data.get('email'))
        if existing is not None:
            if not serializer.is_verbatim_replay(
                existing,
                username=data.get('username'),
                password=data.get('password'),
            ):
                # Do not confirm *which* field collided. Naming `email` turns
                # this endpoint into a membership oracle for the whole user
                # table: the DRF `username` uniqueness check below is a second,
                # independent way to ask the same question. Both are
                # deliberately indistinguishable, so the response says only
                # that the account could not be created.
                raise ValidationError(
                    {
                        'detail': (
                            'Unable to create account with the provided '
                            'details.'
                        )
                    }
                )
            # Reached only with the account's exact username *and* password, so
            # the caller has proven they own this record and may see it — which
            # is why this uses the private serializer rather than the public one
            # the stories API embeds.
            return Response(
                {
                    'user': PrivateUserSerializer(existing).data,
                    'message': 'Account already exists. Sign in at /api/auth/token/.',
                },
                status=status.HTTP_200_OK,
            )

        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {
                'user': PrivateUserSerializer(user).data,
                'message': 'Account created. Sign in at /api/auth/token/.',
            },
            status=status.HTTP_201_CREATED,
        )


# ---------------------------------------------------------------------------
# Current user
# ---------------------------------------------------------------------------
@extend_schema(
    request=PrivateUserSerializer,
    responses={200: PrivateUserSerializer},
)
class MeView(APIView):
    """GET/PATCH/DELETE /api/users/me/ — the authenticated user's profile.

    GET    — return the current profile, including this reader's own email.
    PATCH  — update profile fields (role is NOT editable here; see admin).
    DELETE — permanently delete the account & data (privacy compliance,
             Task 2.3).
    """
    # Declared for drf-spectacular; the view builds this serializer by hand in
    # each method, and an APIView without `serializer_class` is skipped when
    # the schema is generated, so /api/users/me/ was missing from the document.
    serializer_class = PrivateUserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(PrivateUserSerializer(request.user).data)

    def patch(self, request):
        serializer = PrivateUserSerializer(
            request.user,
            data=request.data,
            partial=True,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        # Prevent users from self-elevating their role.
        if 'role' in serializer.validated_data:
            return Response(
                {'role': ['Role changes require administrator approval.']},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer.save()
        return Response(serializer.data)

    def delete(self, request):
        request.user.delete()
        # A 204 response carries no body by definition. Returning one anyway
        # produced a response that every client library treats differently:
        # `fetch` on the web throws on a 204 that has a body, and several HTTP
        # stacks strip the body *and* log a protocol warning. The 204 itself
        # already means "done" — the username in the message added nothing the
        # client did not already know.
        return Response(status=status.HTTP_204_NO_CONTENT)
