from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import (
    OpenApiParameter,
    extend_schema,
    inline_serializer,
)
from rest_framework import generics, permissions, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from config.client_ip import get_client_ip

from .models import Artifact, QRCodeScan
from .serializers import (
    ArtifactCreateUpdateSerializer,
    ArtifactDetailSerializer,
    ArtifactListSerializer,
    ArtifactWorklistSerializer,
    QRCodeGenerateSerializer,
    QRCodeScanSerializer,
    QRWorklistGenerateSerializer,
    QRWorklistSerializer,
)
from .services.qr_generator import generate_artifact_qr
from .services.qr_worklist import (
    QR_WORKLIST_LIMIT,
    generate_qr_for_artifacts,
    missing_slugs,
    qr_worklist_data,
)


class IsInstitutionManagerOrAbove(permissions.BasePermission):
    """Allow Institution Managers and Admins to manage artifacts."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.role in ('institution_manager', 'admin')


class ArtifactViewSet(viewsets.ModelViewSet):
    """Artifact CRUD with QR code generation.

    Endpoints:
      GET    /api/artifacts/             — list published artifacts
      POST   /api/artifacts/             — create artifact (manager/admin)
      GET    /api/artifacts/{slug}/      — retrieve artifact detail
      PUT    /api/artifacts/{slug}/      — update artifact
      DELETE /api/artifacts/{slug}/      — delete artifact
      POST   /api/artifacts/{slug}/generate-qr/  — generate QR code
      POST   /api/artifacts/{slug}/scan/         — record a scan
      GET    /api/artifacts/{slug}/scans/        — list scans
    """

    lookup_field = 'slug'

    def get_serializer_class(self):
        if self.action == 'list':
            return ArtifactListSerializer
        elif self.action in ('create', 'update', 'partial_update'):
            return ArtifactCreateUpdateSerializer
        return ArtifactDetailSerializer

    # Actions that mutate artifact data and therefore require a manager.
    # `generate_qr` belongs here because the SVG format persists the generated
    # code onto the artifact (`qr_code_svg`); it must not be reachable without
    # authentication. Read/scan actions stay public.
    _MANAGER_ACTIONS = (
        'create',
        'update',
        'partial_update',
        'destroy',
        'generate_qr',
    )

    def get_permissions(self):
        if self.action in self._MANAGER_ACTIONS:
            return [IsInstitutionManagerOrAbove()]
        return [permissions.AllowAny()]

    def get_queryset(self):
        qs = Artifact.objects.select_related('created_by').prefetch_related('stories')
        if self.request.user.is_authenticated and self.request.user.role in (
            'institution_manager', 'admin',
        ):
            return qs  # Managers see all artifacts
        return qs.filter(is_published=True)  # Others see published only

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    @action(detail=True, methods=['post'])
    def generate_qr(self, request, slug=None):
        """Generate QR code for an artifact."""
        artifact = self.get_object()
        serializer = QRCodeGenerateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        # The rules live in the service, not here: the web admin dashboard
        # calls the same function, and a change to what "persisted" means must
        # not be able to land on one surface only.
        try:
            result = generate_artifact_qr(
                artifact,
                fmt=data.get('format', 'svg'),
                foreground=data.get('foreground', '#C85A32'),
                background=data.get('background', '#FFFFFF'),
            )
        except ValueError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        if result['format'] == 'png':
            return HttpResponse(
                result['png_bytes'],
                content_type='image/png',
                headers={
                    'Content-Disposition': f'attachment; filename="qr_{artifact.slug}.png"',
                },
            )
        return Response({
            key: value
            for key, value in result.items()
            if key in ('svg', 'data_uri', 'deep_link')
        })

    @action(detail=True, methods=['post'])
    def scan(self, request, slug=None):
        """Record a QR code scan."""
        artifact = self.get_object()

        scan = QRCodeScan.objects.create(
            artifact=artifact,
            user=request.user if request.user.is_authenticated else None,
            device_type=request.data.get('device_type', ''),
            ip_address=self._get_client_ip(request),
            user_agent=request.META.get('HTTP_USER_AGENT', ''),
            latitude=request.data.get('latitude'),
            longitude=request.data.get('longitude'),
        )

        return Response(
            QRCodeScanSerializer(scan).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['get'])
    def scans(self, request, slug=None):
        """List scans for an artifact."""
        artifact = self.get_object()

        # Only managers/admins can see scan analytics
        if request.user.role not in ('institution_manager', 'admin'):
            return Response(
                {'error': 'Permission denied'},
                status=status.HTTP_403_FORBIDDEN,
            )

        scans = artifact.scans.all()[:100]
        return Response(QRCodeScanSerializer(scans, many=True).data)

    def _get_client_ip(self, request):
        return get_client_ip(request)


@extend_schema(
    responses={200: QRWorklistSerializer},
    description=(
        'Artifacts ordered by "has no printable QR code yet", mirroring the web '
        'admin dashboard section. Manager/admin only.'
    ),
)
class ArtifactQRWorklistView(generics.GenericAPIView):
    """`GET /api/artifacts/qr/worklist/` — the curator's worklist.

    Read-only. A QR code is not a record: it is derived from the artifact's
    deep link and only exists once it is generated, so there is nothing here to
    create. The ordering and the limit are `qr_codes.services.qr_worklist`'s,
    the same ones the server-rendered dashboard uses — the two screens showing
    different lists of the same museum is the failure this endpoint exists to
    prevent.
    """

    serializer_class = QRWorklistSerializer
    permission_classes = [IsInstitutionManagerOrAbove]

    def get(self, request):
        data = qr_worklist_data()
        return Response({
            'artifacts': ArtifactWorklistSerializer(
                data['qr_artifacts'], many=True,
            ).data,
            'total': data['qr_total'],
            'generated': data['qr_generated'],
            'truncated': data['qr_truncated'],
        })


@extend_schema(
    request=QRWorklistGenerateSerializer,
    responses={200: inline_serializer(
        name='QRWorklistGenerateResponse',
        fields={
            'generated': serializers.ListField(
                child=serializers.CharField(),
                help_text='Slugs a code was generated for.',
            ),
            'missing': serializers.ListField(
                child=serializers.CharField(),
                help_text='Requested slugs that do not resolve.',
            ),
            'skipped': serializers.BooleanField(
                help_text='True when no slugs were given and nothing was missing.',
            ),
        },
    )},
    description=(
        'Generate QR codes for named artifacts, or for everything still '
        'missing when `slugs` is omitted. Manager/admin only.'
    ),
)
class ArtifactQRWorklistGenerateView(generics.GenericAPIView):
    """`POST /api/artifacts/qr/worklist/generate/` — batch generation.

    Separate from the per-artifact `generate_qr` because a curator with a
    printer and a tray of unlabelled objects wants one request, and because the
    batch is bounded: a national collection must not be regenerable in a
    single call. With no `slugs` the bound is the worklist limit; with them, it
    is however many the caller asked for.
    """

    serializer_class = QRWorklistGenerateSerializer
    permission_classes = [IsInstitutionManagerOrAbove]

    def post(self, request):
        serializer = QRWorklistGenerateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        slugs = list(serializer.validated_data.get('slugs') or [])
        if not slugs:
            slugs = missing_slugs(QR_WORKLIST_LIMIT)
            if not slugs:
                return Response({'generated': [], 'missing': [], 'skipped': True})

        generated, missing = generate_qr_for_artifacts(slugs)
        return Response({
            'generated': [artifact.slug for artifact in generated],
            'missing': missing,
            'skipped': False,
        })


@extend_schema(
    parameters=[
        OpenApiParameter(
            name='path',
            type=str,
            location=OpenApiParameter.QUERY,
            required=True,
            description='Deep link path, e.g. /artifact/my-artifact.',
        ),
    ],
    responses={
        200: ArtifactDetailSerializer,
        400: inline_serializer(
            name='ArtifactLookupBadRequest',
            fields={'error': serializers.CharField()},
        ),
        404: inline_serializer(
            name='ArtifactLookupNotFound',
            fields={'error': serializers.CharField()},
        ),
    },
)
class ArtifactLookupByDeepLinkView(generics.GenericAPIView):
    """Look up an artifact by its deep link path.

    Used by the frontend deep link handler:
      GET /api/artifacts/lookup/?path=/artifact/my-artifact
    """
    serializer_class = ArtifactDetailSerializer
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        path = request.query_params.get('path', '')
        if not path:
            return Response(
                {'error': 'Missing path parameter'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Strip leading slash if present
        path = path.lstrip('/')

        # Look up by deep_link_path
        artifact = Artifact.objects.filter(
            deep_link_path=f'/{path}',
            is_published=True,
        ).first()

        if not artifact:
            # Also try slug-based lookup
            slug = path.split('/')[-1]
            artifact = Artifact.objects.filter(
                slug=slug,
                is_published=True,
            ).first()

        if not artifact:
            return Response(
                {'error': 'Artifact not found'},
                status=status.HTTP_404_NOT_FOUND,
            )

        return Response(ArtifactDetailSerializer(artifact).data)


@extend_schema(
    parameters=[
        OpenApiParameter(
            name='device',
            type=str,
            location=OpenApiParameter.QUERY,
            required=False,
            description='Device label recorded with the scan, if the caller sends one.',
        ),
    ],
    responses={200: ArtifactDetailSerializer},
)
class QRCodeRedirectView(generics.GenericAPIView):
    """Handle deep link redirects.

    This endpoint is hit when a user scans a QR code:
      /qr/<slug>/ → redirects to artifact detail in-app
    """
    serializer_class = ArtifactDetailSerializer
    permission_classes = [permissions.AllowAny]

    def get(self, request, slug):
        artifact = get_object_or_404(Artifact, slug=slug, is_published=True)

        # Record the scan
        QRCodeScan.objects.create(
            artifact=artifact,
            user=request.user if request.user.is_authenticated else None,
            device_type=request.query_params.get('device', ''),
            ip_address=self._get_client_ip(request),
            user_agent=request.META.get('HTTP_USER_AGENT', ''),
        )

        # Return artifact data (frontend will handle in-app navigation)
        return Response(ArtifactDetailSerializer(artifact).data)

    def _get_client_ip(self, request):
        return get_client_ip(request)
