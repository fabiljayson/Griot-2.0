from django.conf import settings
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Artifact, QRCodeScan
from .serializers import (
    ArtifactCreateUpdateSerializer,
    ArtifactDetailSerializer,
    ArtifactListSerializer,
    QRCodeGenerateSerializer,
    QRCodeScanSerializer,
)
from .services.qr_generator import get_qr_generator


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

    def get_permissions(self):
        if self.action in ('create', 'update', 'partial_update', 'destroy'):
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

        qr_gen = get_qr_generator()
        fg = data.get('foreground', '#C85A32')
        bg = data.get('background', '#FFFFFF')
        fmt = data.get('format', 'svg')

        deep_link = artifact.qr_deep_link

        if fmt == 'svg':
            svg = qr_gen.generate_svg(deep_link, foreground=fg, background=bg)
            artifact.qr_code_svg = svg
            artifact.save(update_fields=['qr_code_svg'])
            return Response({
                'svg': svg,
                'deep_link': deep_link,
            })

        elif fmt == 'png':
            png_bytes = qr_gen.generate_png(
                deep_link, foreground=fg, background=bg,
            )
            return HttpResponse(
                png_bytes,
                content_type='image/png',
                headers={
                    'Content-Disposition': f'attachment; filename="qr_{artifact.slug}.png"',
                },
            )

        elif fmt == 'data_uri':
            data_uri = qr_gen.generate_data_uri(
                deep_link, foreground=fg, background=bg,
            )
            return Response({
                'data_uri': data_uri,
                'deep_link': deep_link,
            })

        return Response(
            {'error': 'Invalid format'},
            status=status.HTTP_400_BAD_REQUEST,
        )

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
        x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded:
            return x_forwarded.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR')


class ArtifactLookupByDeepLinkView(generics.GenericAPIView):
    """Look up an artifact by its deep link path.

    Used by the frontend deep link handler:
      GET /api/artifacts/lookup/?path=/artifact/my-artifact
    """
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


class QRCodeRedirectView(generics.GenericAPIView):
    """Handle deep link redirects.

    This endpoint is hit when a user scans a QR code:
      /qr/<slug>/ → redirects to artifact detail in-app
    """
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
        x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded:
            return x_forwarded.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR')
