import logging

from django.core.files.base import ContentFile
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import (
    OpenApiParameter,
    OpenApiResponse,
    extend_schema,
)
from rest_framework import generics, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.response import Response

from qr_codes.models import Artifact
from stories.models import Story

from . import quota
from .models import AudioNarrationJob, VideoGenerationJob, normalise_engine
from .serializers import (
    AudioNarrationCreateSerializer,
    AudioNarrationJobSerializer,
    VideoGenerationCreateSerializer,
    VideoGenerationJobSerializer,
    VoiceSerializer,
)
from .services.luma_ai import LumaAIError, _normalise_progress, get_luma_service
from .services.tts import (
    TTSGenerationError,
    build_artifact_script,
    get_tts_service,
    resolve_language,
    strip_markdown,
)

logger = logging.getLogger(__name__)


class IsOwnerOrReadOnly(permissions.BasePermission):
    """Allow owners to edit their own jobs."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.user == request.user


@extend_schema(
    parameters=[OpenApiParameter('id', int, OpenApiParameter.PATH)],
)
class VideoGenerationViewSet(viewsets.ModelViewSet):
    """ViewSet for video generation jobs."""

    serializer_class = VideoGenerationJobSerializer
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrReadOnly]

    def get_queryset(self):
        # Users can only see their own jobs, admins can see all
        if self.request.user.role == 'admin':
            return VideoGenerationJob.objects.all()
        return VideoGenerationJob.objects.filter(user=self.request.user)

    def get_serializer_class(self):
        if self.action == 'create':
            return VideoGenerationCreateSerializer
        return VideoGenerationJobSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        story = get_object_or_404(Story, id=data['story_id'])

        # Any signed-in user may render a story that is already public; a
        # draft stays private to its author and the managing roles. Mirrors
        # the audio narration rule so the two features agree.
        if (
            story.author != request.user
            and request.user.role not in ('admin', 'institution_manager')
            and story.status != Story.Status.PUBLISHED
        ):
            raise DRFPermissionDenied(
                'You can only generate videos for your own or published stories.'
            )

        # Luma bills per generation, so cap how much one account can start
        # per day regardless of the ownership rule above. Shared with the web
        # actions via media_app.quota so the two paths cannot drift.
        daily_cap = quota.video_cap()
        if not quota.video_within_cap(request.user):
            return Response(
                {
                    'detail': (
                        'You have reached your daily video generation '
                        f'limit of {daily_cap}. Please try again tomorrow.'
                    )
                },
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        # Submit to Luma AI (mock service when no key is configured and
        # LUMA_ALLOW_MOCK permits it). Resolving the service inside the try
        # matters: with no key on a production config, get_luma_service()
        # raises rather than handing back a mock that would report this job
        # completed with an unplayable URL. The job row is created after the
        # call so `engine` can be stamped from whichever service answered — a
        # mock run must never be credited to Dream Machine.
        try:
            luma_service = get_luma_service()
            result = luma_service.submit_video_generation(
                prompt=data['prompt'],
                duration=data.get('duration', 10),
            )
        except LumaAIError as exc:
            # Record why the generation died instead of leaving a permanently
            # pending job the user can never cancel.
            VideoGenerationJob.objects.create(
                user=request.user,
                story=story,
                prompt=data['prompt'],
                status=VideoGenerationJob.Status.FAILED,
                error_message=str(exc),
            )
            return Response(
                {'detail': f'Video generation could not be started: {exc}'},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        # Update job with Luma AI details
        job = VideoGenerationJob.objects.create(
            user=request.user,
            story=story,
            prompt=data['prompt'],
            luma_job_id=result['id'],
            engine=normalise_engine(luma_service, 'video'),
        )
        if result.get('status') == VideoGenerationJob.Status.FAILED:
            job.status = VideoGenerationJob.Status.FAILED
            job.error_message = result.get('error', 'Luma AI rejected the request')
        else:
            job.status = VideoGenerationJob.Status.PROCESSING
        job.save()

        out_serializer = VideoGenerationJobSerializer(
            job, context=self.get_serializer_context()
        )
        return Response(out_serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        """Cancel a video generation job."""
        job = self.get_object()

        if job.status not in (
            VideoGenerationJob.Status.PENDING,
            VideoGenerationJob.Status.PROCESSING,
        ):
            return Response(
                {'error': 'Job cannot be cancelled'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Cancel via Luma AI service. If the server has no Luma configured
        # there is nothing remote to cancel, but the user's intent still has
        # to be honoured locally, so fall through to the same state update
        # rather than erroring out.
        try:
            luma_service = get_luma_service()
            luma_service.cancel_job(job.luma_job_id)
        except LumaAIError as exc:
            logger.warning('Luma cancel skipped for job %s: %s', job.pk, exc)

        job.status = VideoGenerationJob.Status.FAILED
        job.error_message = 'Cancelled by user'
        job.save()

        return Response({'status': 'cancelled'})

    @action(detail=True, methods=['get'])
    def status(self, request, pk=None):
        """Check video generation status."""
        job = self.get_object()

        # Poll Luma AI for status update
        if job.luma_job_id:
            luma_status = None
            try:
                luma_service = get_luma_service()
                luma_status = luma_service.get_job_status(job.luma_job_id)
            except LumaAIError as exc:
                # A server that has lost its Luma configuration must not 500
                # a poll: the client loops on this endpoint and would read the
                # error as a dead job. Report the stored state unchanged.
                logger.warning('Luma poll skipped for job %s: %s', job.pk, exc)

            if luma_status is not None:
                # Update job based on Luma AI response
                if luma_status.get('status') == 'completed':
                    job.status = VideoGenerationJob.Status.COMPLETED
                    job.video_url = luma_status.get('video_url', '')
                    job.thumbnail_url = luma_status.get('thumbnail_url', '')
                    job.duration = luma_status.get('duration', 0)
                    job.progress_percent = 100
                    if not job.completed_at:
                        job.completed_at = timezone.now()
                elif luma_status.get('status') == 'failed':
                    job.status = VideoGenerationJob.Status.FAILED
                    job.error_message = luma_status.get('error', 'Unknown error')
                else:
                    # Persist progress while rendering. Without this the field
                    # stays 0 for the whole render and the client's progress bar
                    # reads as a hung request.
                    job.progress_percent = _normalise_progress(
                        luma_status.get('progress'), luma_status.get('status', '')
                    )
                    if job.status == VideoGenerationJob.Status.PENDING:
                        job.status = VideoGenerationJob.Status.PROCESSING
                    if not job.started_at:
                        job.started_at = timezone.now()

                job.save()

        serializer = self.get_serializer(job)
        return Response(serializer.data)


@extend_schema(
    parameters=[OpenApiParameter('id', int, OpenApiParameter.PATH)],
)
class AudioNarrationViewSet(viewsets.ModelViewSet):
    """ViewSet for audio narration jobs."""

    serializer_class = AudioNarrationJobSerializer
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrReadOnly]

    def get_queryset(self):
        if self.request.user.role == 'admin':
            return (
                AudioNarrationJob.objects.select_related('story', 'artifact').all()
            )
        return AudioNarrationJob.objects.select_related(
            'story', 'artifact'
        ).filter(user=self.request.user)

    def get_serializer_class(self):
        if self.action == 'create':
            return AudioNarrationCreateSerializer
        return AudioNarrationJobSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        story = None
        artifact = None
        narration_text = ''
        narration_slug = 'narration'

        # --- Story-based narration ---
        if data.get('story_id'):
            story = get_object_or_404(Story, id=data['story_id'])

            # Story authors always can; managers/admins too. Other
            # authenticated users may narrate published stories.
            if (
                story.author != request.user
                and request.user.role not in ('admin', 'institution_manager')
                and story.status != Story.Status.PUBLISHED
            ):
                raise DRFPermissionDenied(
                    'You can only generate audio for your own or published stories.'
                )

            narration_text = strip_markdown(story.content)
            narration_slug = story.slug or story.title

        # --- Artifact-based narration (audio guide) ---
        elif data.get('artifact_id'):
            artifact = get_object_or_404(Artifact, id=data['artifact_id'])

            if (
                not artifact.is_published
                and request.user.role not in ('admin', 'institution_manager')
            ):
                raise DRFPermissionDenied(
                    'You can only generate audio for published artifacts.'
                )

            narration_text = build_artifact_script(artifact)
            narration_slug = artifact.slug or artifact.title
            # If the artifact has a primary story, link it so the job
            # shows both the artifact and its story.
            if not story:
                story = (
                    artifact.stories
                    .filter(status=Story.Status.PUBLISHED)
                    .order_by('id')
                    .first()
                )

        if not narration_text.strip():
            return Response(
                {'detail': 'There is no text available to narrate.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Normalize the requested language to the code gTTS will actually
        # use, so cached (pre-seeded) narrations are found and reused.
        language = resolve_language(data.get('language', 'en'))

        # Reuse an existing completed narration (e.g. pre-generated by the
        # ``seed_narrations`` command) instead of synthesizing again.
        if artifact is not None:
            existing = (
                AudioNarrationJob.objects
                .filter(
                    artifact=artifact,
                    language=language,
                    status=AudioNarrationJob.Status.COMPLETED,
                )
                .order_by('-created_at')
                .first()
            )
        elif story is not None:
            existing = (
                AudioNarrationJob.objects
                .filter(
                    story=story,
                    artifact__isnull=True,
                    language=language,
                    status=AudioNarrationJob.Status.COMPLETED,
                )
                .order_by('-created_at')
                .first()
            )
        else:
            existing = None

        if existing is not None:
            out_serializer = AudioNarrationJobSerializer(
                existing, context=self.get_serializer_context()
            )
            return Response(out_serializer.data, status=status.HTTP_200_OK)

        # Only a job that actually synthesizes counts against the cap, so the
        # cache hit above stays free and re-reading a story is never throttled.
        # Shared with the web actions via media_app.quota.
        daily_cap = quota.audio_cap()
        if not quota.audio_within_cap(request.user):
            return Response(
                {
                    'detail': (
                        'You have reached your daily audio narration '
                        f'limit of {daily_cap}. Narrations already '
                        'generated for you are still available.'
                    )
                },
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        # Generate real audio with gTTS and store the file.
        tts_service = get_tts_service()
        job = AudioNarrationJob.objects.create(
            user=request.user,
            story=story,
            artifact=artifact,
            narration_text=narration_text,
            language=language,
            speed=data.get('speed', 1.0),
            voice_id=data.get('voice_id', 'default'),
            status=AudioNarrationJob.Status.PROCESSING,
            engine=normalise_engine(tts_service, 'narration'),
        )

        try:
            result = tts_service.submit_narration(
                text=narration_text,
                language=job.language,
                voice_id=job.voice_id,
                speed=job.speed,
                slug=narration_slug,
            )
            job.audio_file.save(
                result['filename'],
                ContentFile(result['audio_bytes']),
                save=False,
            )
            job.duration = result['duration']
            job.file_size = result['file_size']
            job.status = AudioNarrationJob.Status.COMPLETED
            job.completed_at = timezone.now()
        except TTSGenerationError as exc:
            job.status = AudioNarrationJob.Status.FAILED
            job.error_message = str(exc)
        job.save()

        out_serializer = AudioNarrationJobSerializer(
            job, context=self.get_serializer_context()
        )
        return Response(out_serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'])
    def status(self, request, pk=None):
        """Check audio narration status."""
        job = self.get_object()
        serializer = self.get_serializer(job)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def available_voices(self, request):
        """List available voices for TTS."""
        tts_service = get_tts_service()
        voices = tts_service.list_voices()
        serializer = VoiceSerializer(voices, many=True)
        return Response(serializer.data)


@extend_schema(
    parameters=[
        OpenApiParameter(
            name='job_type',
            type=str,
            location=OpenApiParameter.PATH,
            required=True,
            enum=['video', 'audio'],
        ),
        OpenApiParameter(
            name='job_id',
            type=int,
            location=OpenApiParameter.PATH,
            required=True,
        ),
    ],
    # The body is a VideoGenerationJob or an AudioNarrationJob depending on
    # `job_type`, so both are declared and the operation documented as a
    # oneOf by drf-spectacular.
    responses={
        200: OpenApiResponse(
            response=VideoGenerationJobSerializer,
            description='Video job state.',
        ),
    },
)
class MediaStatusView(generics.GenericAPIView):
    """Check status of a media generation job."""
    # Declared for the schema; the concrete serializer is chosen per
    # `job_type` inside `get`, which a single `serializer_class` cannot express.
    serializer_class = VideoGenerationJobSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, job_type, job_id):
        """Check status of a video or audio job."""
        if job_type == 'video':
            job = get_object_or_404(
                VideoGenerationJob,
                id=job_id,
                user=request.user,
            )
            serializer = VideoGenerationJobSerializer(job)
        elif job_type == 'audio':
            job = get_object_or_404(
                AudioNarrationJob,
                id=job_id,
                user=request.user,
            )
            serializer = AudioNarrationJobSerializer(job)
        else:
            return Response(
                {'error': 'Invalid job type'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response(serializer.data)
