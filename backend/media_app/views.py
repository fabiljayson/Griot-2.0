from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status, viewsets
from rest_framework.exceptions import PermissionDenied as DRFPermissionDenied
from rest_framework.decorators import action
from rest_framework.response import Response

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
from .services.tts import get_tts_service


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
            return AudioNarrationJob.objects.all()
        return AudioNarrationJob.objects.filter(user=self.request.user)

    def get_serializer_class(self):
        if self.action == 'create':
            return AudioNarrationCreateSerializer
        return AudioNarrationJobSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        story = get_object_or_404(Story, id=data['story_id'])

        # Check permissions
        if story.author != request.user and request.user.role not in (
            'admin',
            'institution_manager',
        ):
            raise DRFPermissionDenied(
                'You can only generate audio for your own stories.'
            )

        # Create job
        job = AudioNarrationJob.objects.create(
            user=request.user,
            story=story,
            language=data.get('language', 'en'),
            speed=data.get('speed', 1.0),
            voice_id=data.get('voice_id', 'default'),
            status=AudioNarrationJob.Status.PROCESSING,
        )

        # Submit to TTS service
        tts_service = get_tts_service()
        result = tts_service.submit_narration(
            text=story.content,
            language=job.language,
            voice_id=job.voice_id,
            speed=job.speed,
        )

        # For mock demo, mark as completed immediately with a mock URL
        job.status = AudioNarrationJob.Status.COMPLETED
        job.audio_url = f'https://storage.example.com/audio/{job.id}.mp3'
        job.duration = max(30, len(story.content) // 8)  # rough estimate
        job.file_size = 1500000
        job.save()

        out_serializer = AudioNarrationJobSerializer(
            job, context=self.get_serializer_context()
        )
        return Response(out_serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'])
    def status(self, request, pk=None):
        """Check audio narration status."""
        job = self.get_object()

        # For mock, just mark as completed for demo
        if job.status == AudioNarrationJob.Status.PROCESSING:
            job.status = AudioNarrationJob.Status.COMPLETED
            job.audio_url = f'https://storage.example.com/audio/{job.id}.mp3'
            job.duration = 120  # Mock duration
            job.file_size = 1500000  # Mock file size
            job.save()

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
