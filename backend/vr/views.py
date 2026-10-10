"""VR HTTP endpoints.

The two halves of this module have different trust models, which is why they are
written differently:

* `VRLaunchView` runs on the **phone**: authenticated with the reader's own JWT,
  throttled per user, and it only *issues* a credential.
* `VRLaunchExchangeView` runs on the **headset**: unauthenticated by design,
  because the launch token *is* the credential, and every failure mode gets its
  own status and code so Unity can say something useful instead of "failed".

Read endpoints accept any valid token (a reader's JWT or a VR session token):
the payloads are the same public artifact and story data the website serves, so
requiring the VR scope there would add friction and protect nothing.
"""

from django.shortcuts import get_object_or_404
from drf_spectacular.utils import OpenApiParameter, extend_schema, inline_serializer
from rest_framework import generics, serializers, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from gamification.models import UserProfile
from qr_codes.models import Artifact

from .models import VRSession
from .permissions import IsAuthenticatedForVR, IsVRSessionToken
from .serializers import (
    VRArtifactDetailResponseSerializer,
    VRExchangeRequestSerializer,
    VRExchangeResponseSerializer,
    VRExperiencePayloadSerializer,
    VRExperienceSummarySerializer,
    VRLaunchRequestSerializer,
    VRLaunchResponseSerializer,
    VRLocationSerializer,
    VRProgressEntrySerializer,
    VRProgressRequestSerializer,
    VRSessionCompleteRequestSerializer,
    VRSessionCompleteResponseSerializer,
    VRSessionSerializer,
    VRSessionStartRequestSerializer,
)
from .services.experience_payload import (
    artifact_payload,
    experience_locations,
    experience_payload,
    experience_summary,
)
from .services.experiences import (
    AmbiguousVRExperience,
    NoVRExperience,
    active_experiences,
    active_experiences_for_artifact,
    find_experience_by_key,
    get_experience_or_404,
    resolve_launch_experience,
)
from .services.launch_tokens import (
    ExpiredLaunchToken,
    InvalidLaunchToken,
    UsedLaunchToken,
    build_deep_link,
    consume_launch_token,
    issue_launch_token,
)
from .services.progress import (
    SessionNotActive,
    progress_entries,
    record_progress,
    session_for_token,
)
from .services.session_tokens import mint_session_token
from .services.sessions import (
    InvalidCompletionStatus,
    InvalidSessionArtifacts,
    complete_session,
    find_active_session,
    start_session,
)


def _error_schema(name: str):
    """Typed error body so the published schema matches what we actually send."""
    return inline_serializer(
        name=name,
        fields={
            'error': serializers.CharField(help_text='Human-readable reason.'),
            'code': serializers.CharField(help_text='Stable machine-readable reason.'),
        },
    )


def _error(code: str, message: str, http_status: int) -> Response:
    return Response({'error': message, 'code': code}, status=http_status)


def _resolve_artifact(key):
    """Look up a published artifact by id or slug, or None.

    Published-only on purpose: an unpublished artifact is not yet a public fact,
    and a VR client is the least auditable surface in the system.
    """
    if key is None:
        return None
    key = str(key).strip()
    if not key:
        return None
    queryset = Artifact.objects.filter(is_published=True)
    if key.isdigit():
        return queryset.filter(pk=int(key)).first()
    return queryset.filter(slug=key).first()


# ---------------------------------------------------------------------------
# Launch (phone side)
# ---------------------------------------------------------------------------
@extend_schema(
    request=VRLaunchRequestSerializer,
    responses={
        201: VRLaunchResponseSerializer,
        400: _error_schema('VRLaunchBadRequest'),
        401: _error_schema('VRLaunchUnauthorized'),
        404: _error_schema('VRLaunchNotFound'),
        409: _error_schema('VRLaunchAmbiguous'),
    },
    description=(
        'Mint a single-use VR launch token for the signed-in reader. The response '
        'carries the `griotvr://` deep link to hand to Android. The token expires '
        'in seconds, is bound to this user and this experience, and works once.'
    ),
)
class VRLaunchView(APIView):
    """`POST /api/vr/launch/` — issue a VR launch token."""

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'vr_launch'

    def post(self, request):
        serializer = VRLaunchRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        artifact = None
        if data.get('artifact'):
            artifact = _resolve_artifact(data['artifact'])
            if artifact is None:
                return _error(
                    'artifact_not_found',
                    'That artifact is not available.',
                    status.HTTP_404_NOT_FOUND,
                )

        try:
            experience = resolve_launch_experience(
                experience_key=data.get('experience'),
                artifact=artifact,
            )
        except AmbiguousVRExperience as exc:
            return _error(exc.code, str(exc), status.HTTP_409_CONFLICT)
        except NoVRExperience as exc:
            return _error(exc.code, str(exc), status.HTTP_404_NOT_FOUND)

        issued = issue_launch_token(
            user=request.user,
            experience=experience,
            artifact=artifact,
        )

        return Response(
            VRLaunchResponseSerializer({
                'token': issued.token,
                'expires_at': issued.expires_at,
                'expires_in': issued.expires_in,
                'deep_link': build_deep_link(
                    token=issued.token,
                    experience=experience,
                    artifact=artifact,
                ),
                'experience': experience_summary(experience),
                'artifact': artifact_payload(artifact) if artifact else None,
            }).data,
            status=status.HTTP_201_CREATED,
        )


# ---------------------------------------------------------------------------
# Exchange (headset side)
# ---------------------------------------------------------------------------
@extend_schema(
    request=VRExchangeRequestSerializer,
    responses={
        200: VRExchangeResponseSerializer,
        400: _error_schema('VRExchangeBadRequest'),
        409: _error_schema('VRExchangeConflict'),
        410: _error_schema('VRExchangeGone'),
    },
    description=(
        'Burn a launch token and open a VR session. Returns a short-lived '
        'VR-scoped JWT (`scope=vr`) and the full experience payload. No refresh '
        'token is issued: VR access is bounded by design.'
    ),
)
class VRLaunchExchangeView(APIView):
    """`POST /api/vr/launch/exchange/` — token → session + experience."""

    # The launch token is the credential. Authenticating with a header as well
    # would let a stale token on the device silently change whose session this
    # is, so authentication is off rather than "optional".
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'vr_token'

    def post(self, request):
        serializer = VRExchangeRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            launch = consume_launch_token(token=serializer.validated_data['token'])
        except UsedLaunchToken as exc:
            return _error(exc.code, str(exc), status.HTTP_409_CONFLICT)
        except ExpiredLaunchToken as exc:
            return _error(exc.code, str(exc), status.HTTP_410_GONE)
        except InvalidLaunchToken as exc:
            return _error(exc.code, str(exc), status.HTTP_400_BAD_REQUEST)

        if not launch.experience.is_active:
            # A curator pulled the experience between issue and exchange. The
            # token is already burnt, which is correct — a launch was attempted.
            return _error(
                'experience_unavailable',
                'That experience is no longer available.',
                status.HTTP_410_GONE,
            )

        session = start_session(
            user=launch.user,
            experience=launch.experience,
            launch_token=launch,
            device_model=serializer.validated_data.get('device_model') or '',
        )
        access_token, expires_in = mint_session_token(user=launch.user, session=session)

        return Response(
            VRExchangeResponseSerializer({
                'access_token': access_token,
                'expires_in': expires_in,
                'session': session,
                'experience': experience_payload(launch.experience),
            }).data,
        )


# ---------------------------------------------------------------------------
# Content reads (headset side)
# ---------------------------------------------------------------------------
@extend_schema(
    parameters=[
        OpenApiParameter(
            name='artifact',
            type=str,
            location=OpenApiParameter.QUERY,
            required=False,
            description='Only experiences containing this artifact (id or slug).',
        ),
    ],
    responses=VRExperienceSummarySerializer(many=True),
    description='Active VR experiences, newest first.',
)
class VRExperienceListView(generics.ListAPIView):
    """`GET /api/vr/experiences/` — what can be launched into."""

    serializer_class = VRExperienceSummarySerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        queryset = active_experiences()
        artifact_key = self.request.query_params.get('artifact')
        if artifact_key:
            artifact = _resolve_artifact(artifact_key)
            if artifact is None:
                return queryset.none()
            queryset = queryset.filter(placements__artifact=artifact).distinct()
        return queryset


@extend_schema(
    responses={
        200: VRExperiencePayloadSerializer,
        404: _error_schema('VRExperienceNotFound'),
    },
    description='Everything Unity needs to load one experience, by id or slug.',
)
class VRExperienceDetailView(generics.GenericAPIView):
    """`GET /api/vr/experiences/<id|slug>/` — the scene manifest."""

    serializer_class = VRExperiencePayloadSerializer
    permission_classes = [IsAuthenticatedForVR]

    def get(self, request, key):
        experience = get_experience_or_404(key)
        return Response(VRExperiencePayloadSerializer(experience_payload(experience)).data)


@extend_schema(
    responses={
        200: VRArtifactDetailResponseSerializer,
        404: _error_schema('VRArtifactNotFound'),
    },
    description=(
        'One artifact, its published stories, and the active experiences it '
        'appears in. Id or slug.'
    ),
)
class VRArtifactDetailView(generics.GenericAPIView):
    """`GET /api/vr/artifacts/<id|slug>/` — artifact detail for VR."""

    serializer_class = VRArtifactDetailResponseSerializer
    permission_classes = [IsAuthenticatedForVR]

    def get(self, request, key):
        artifact = _resolve_artifact(key)
        if artifact is None:
            return _error(
                'artifact_not_found',
                'That artifact is not available.',
                status.HTTP_404_NOT_FOUND,
            )

        payload = artifact_payload(artifact)
        payload['experiences'] = [
            experience_summary(experience)
            for experience in active_experiences_for_artifact(artifact)
        ]
        return Response(VRArtifactDetailResponseSerializer(payload).data)


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------
@extend_schema(
    request=VRSessionStartRequestSerializer,
    responses={
        200: VRSessionSerializer,
        201: VRSessionSerializer,
        404: _error_schema('VRSessionStartNotFound'),
    },
    description=(
        'Open a session, or return the reader’s existing open session for the '
        'same experience (200) so a reconnect cannot start — and be paid for — '
        'a second visit.'
    ),
)
class VRSessionStartView(APIView):
    """`POST /api/vr/sessions/` — start or resume a session.

    Requires the VR-scoped token rather than any reader JWT: a session is a
    headset concept, and this is what makes the `scope` claim load-bearing
    instead of decorative.
    """

    permission_classes = [IsVRSessionToken]

    def post(self, request):
        serializer = VRSessionStartRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        experience = find_experience_by_key(serializer.validated_data['experience'])
        if experience is None:
            return _error(
                'experience_not_found',
                'That experience is not available.',
                status.HTTP_404_NOT_FOUND,
            )

        existing = find_active_session(user=request.user, experience=experience)
        if existing is not None:
            return Response(VRSessionSerializer(existing).data, status=status.HTTP_200_OK)

        session = start_session(user=request.user, experience=experience)
        return Response(
            VRSessionSerializer(session).data,
            status=status.HTTP_201_CREATED,
        )


@extend_schema(
    request=VRSessionCompleteRequestSerializer,
    responses={
        200: VRSessionCompleteResponseSerializer,
        400: _error_schema('VRSessionCompleteBadRequest'),
        404: _error_schema('VRSessionCompleteNotFound'),
    },
    description=(
        'Close a session and record progress. Idempotent: `xp_awarded` reports '
        'what this call paid, which is zero when a retry finds it already paid.'
    ),
)
class VRSessionCompleteView(APIView):
    """`POST /api/vr/sessions/<id>/complete/` — finish a session."""

    permission_classes = [IsVRSessionToken]

    def post(self, request, pk):
        # Filtered by owner, so someone else's session is a 404 rather than a
        # 403 that confirms the row exists.
        session = get_object_or_404(VRSession, pk=pk, user=request.user)

        serializer = VRSessionCompleteRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            session, xp_awarded = complete_session(
                session=session,
                completion_status=data['completion_status'],
                progress=data.get('progress'),
                duration_seconds=data.get('duration_seconds'),
                artifact_ids=data.get('artifacts_viewed'),
            )
        except InvalidCompletionStatus as exc:
            return _error(exc.code, str(exc), status.HTTP_400_BAD_REQUEST)
        except InvalidSessionArtifacts as exc:
            return _error(exc.code, str(exc), status.HTTP_400_BAD_REQUEST)

        profile = UserProfile.objects.filter(user=request.user).first()
        return Response(
            VRSessionCompleteResponseSerializer({
                'session': session,
                'xp_awarded': xp_awarded,
                'profile': profile,
            }).data,
        )


# ---------------------------------------------------------------------------
# Progress
# ---------------------------------------------------------------------------
@extend_schema(
    parameters=[
        OpenApiParameter(
            name='experience',
            type=str,
            location=OpenApiParameter.QUERY,
            required=False,
            description='Only this experience\'s progress (id or slug).',
        ),
    ],
    responses=VRProgressEntrySerializer(many=True),
    methods=['GET'],
    description=(
        'The reader\'s progress, one row per experience: percentage, completed '
        'flag, session count and last visit. Includes experiences that are no '
        'longer active, because progress earned should not disappear.'
    ),
)
@extend_schema(
    request=VRProgressRequestSerializer,
    responses={
        200: VRSessionSerializer,
        400: _error_schema('VRProgressBadRequest'),
        409: _error_schema('VRProgressConflict'),
    },
    methods=['POST', 'PATCH'],
    description=(
        'Record a partial progress update for the session bound to this token '
        '(`sid` claim). `POST` and `PATCH` are aliases — both are upserts on '
        'the open session; opening one is `POST /api/vr/sessions/`. Awards no '
        'XP: only `sessions/<id>/complete/` pays out.'
    ),
)
class VRProgressView(APIView):
    """`GET|POST|PATCH /api/vr/progress/` — read and record progress.

    Reads accept any valid token, like the other content endpoints. Writes
    require the VR-scoped token for the same reason the session endpoints do:
    a full-account JWT must not be able to drive a headset session.
    """

    def get_permissions(self):
        if self.request.method in ('POST', 'PATCH'):
            return [IsVRSessionToken()]
        return [IsAuthenticatedForVR()]

    def get(self, request):
        entries = progress_entries(
            user=request.user,
            experience_key=request.query_params.get('experience'),
        )
        return Response(VRProgressEntrySerializer(entries, many=True).data)

    def post(self, request):
        return self._record(request)

    def patch(self, request):
        return self._record(request)

    def _record(self, request):
        serializer = VRProgressRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        getter = getattr(request.auth, 'get', None)
        sid = getter('sid') if getter is not None else None
        if sid is None:
            # Unreachable for tokens this app mints, but a hand-built token
            # with `scope: vr` and no `sid` must not progress an arbitrary row.
            return _error(
                'missing_session',
                'This token is not bound to a session. Relaunch from the app.',
                status.HTTP_400_BAD_REQUEST,
            )

        session = session_for_token(request.user, sid)

        try:
            session = record_progress(
                session=session,
                progress=data.get('progress'),
                artifact_ids=data.get('artifacts_viewed'),
            )
        except SessionNotActive as exc:
            return _error(exc.code, str(exc), status.HTTP_409_CONFLICT)
        except InvalidSessionArtifacts as exc:
            return _error(exc.code, str(exc), status.HTTP_400_BAD_REQUEST)

        return Response(VRSessionSerializer(session).data)


# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
@extend_schema(
    responses=VRLocationSerializer(many=True),
    description=(
        'Distinct places active experiences live in (museum, region, culture), '
        'each with the experiences it holds. Discovery data, so it is public '
        'like the experience list.'
    ),
)
class VRLocationListView(APIView):
    """`GET /api/vr/locations/` — where the museums are."""

    permission_classes = [AllowAny]

    def get(self, request):
        return Response(VRLocationSerializer(experience_locations(), many=True).data)
