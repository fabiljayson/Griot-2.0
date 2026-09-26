from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import CustomTokenObtainPairSerializer, RegisterSerializer, UserSerializer

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

        existing = serializer.find_by_email(data.get('email'))
        if existing is not None:
            if not serializer.is_verbatim_replay(
                existing,
                username=data.get('username'),
                password=data.get('password'),
            ):
                raise ValidationError(
                    {'email': ['A user with this email already exists.']}
                )
            return Response(
                {
                    'user': UserSerializer(existing).data,
                    'message': 'Account already exists. Sign in at /api/auth/token/.',
                },
                status=status.HTTP_200_OK,
            )

        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {
                'user': UserSerializer(user).data,
                'message': 'Account created. Sign in at /api/auth/token/.',
            },
            status=status.HTTP_201_CREATED,
        )


# ---------------------------------------------------------------------------
# Current user
# ---------------------------------------------------------------------------
class MeView(APIView):
    """GET/PATCH/DELETE /api/users/me/ — the authenticated user's profile.

    GET    — return the current profile.
    PATCH  — update profile fields (role is NOT editable here; see admin).
    DELETE — permanently delete the account & data (privacy compliance,
             Task 2.3).
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        serializer = UserSerializer(
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
        username = request.user.username
        request.user.delete()
        return Response(
            {'message': f'Account "{username}" and associated data deleted.'},
            status=status.HTTP_204_NO_CONTENT,
        )
