from django.core.files.base import ContentFile
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions, status, viewsets
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.decorators import action
from rest_framework.response import Response

from qr_codes.models import Artifact
from stories.models import Story

from .models import AudioNarrationJob, VideoGenerationJob
from .serializers import (
    AudioNarrationCreateSerializer,
    AudioNarrationJobSerializer,
    VideoGenerationCreateSerializer,
    VideoGenerationJobSerializer,
    VoiceSerializer,
)
from .services.luma_ai import get_luma_service
from .services.tts import (
    TTSGenerationError,
    build_artifact_script,
    get_tts_service,
    resolve_language,
    strip_markdown,
)


class IsOwnerOrReadOnly(permissions.BasePermission):
    """Allow owners to edit their own jobs."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.user == request.user


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

        # Check if user can generate video for this story
        if story.author != request.user and request.user.role not in (
            'admin',
            'institution_manager',
        ):
            raise DRFPermissionDenied(
                'You can only generate videos for your own stories.'
            )

        # Create the job
        job = VideoGenerationJob.objects.create(
            user=request.user,
            story=story,
            prompt=data['prompt'],
            status=VideoGenerationJob.Status.PENDING,
        )

        # Submit to mock Luma AI service
        luma_service = get_luma_service()
        result = luma_service.submit_video_generation(
            prompt=data['prompt'],
            duration=data.get('duration', 10),
        )

        # Update job with Luma AI details
        job.luma_job_id = result['id']
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

        # Cancel via Luma AI service
        luma_service = get_luma_service()
        luma_service.cancel_job(job.luma_job_id)

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
            luma_service = get_luma_service()
            luma_status = luma_service.get_job_status(job.luma_job_id)

            # Update job based on Luma AI response
            if luma_status.get('status') == 'completed':
                job.status = VideoGenerationJob.Status.COMPLETED
                job.video_url = luma_status.get('video_url', '')
                job.thumbnail_url = luma_status.get('thumbnail_url', '')
                job.duration = luma_status.get('duration', 0)
            elif luma_status.get('status') == 'failed':
                job.status = VideoGenerationJob.Status.FAILED
                job.error_message = luma_status.get('error', 'Unknown error')

            job.save()

        serializer = self.get_serializer(job)
        return Response(serializer.data)


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

        # Create job
        job = AudioNarrationJob.objects.create(
            user=request.user,
            story=story,
            artifact=artifact,
            narration_text=narration_text,
            language=language,
            speed=data.get('speed', 1.0),
            voice_id=data.get('voice_id', 'default'),
            status=AudioNarrationJob.Status.PROCESSING,
        )

        # Generate real audio with gTTS and store the file.
        tts_service = get_tts_service()
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


class MediaStatusView(generics.GenericAPIView):
    """Check status of a media generation job."""
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
