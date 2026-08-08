from django.conf import settings
from django.db import models


class VideoGenerationJob(models.Model):
    """Track AI video generation jobs via Luma AI Dream Machine."""
    
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'
    
    # --- Ownership ---
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='video_jobs',
    )
    story = models.ForeignKey(
        'stories.Story',
        on_delete=models.CASCADE,
        related_name='video_generations',
    )
    
    # --- Luma AI details ---
    luma_job_id = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Job ID from Luma AI Dream Machine API.',
    )
    prompt = models.TextField(
        help_text='Prompt used for video generation.',
    )
    luma_request_id = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Request ID for tracking.',
    )
    
    # --- Status ---
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
    )
    progress_percent = models.PositiveIntegerField(
        default=0,
        help_text='Generation progress (0-100).',
    )
    
    # --- Output ---
    video_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to the generated video.',
    )
    thumbnail_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to the video thumbnail.',
    )
    duration = models.PositiveIntegerField(
        default=0,
        help_text='Video duration in seconds.',
    )
    error_message = models.TextField(
        blank=True,
        default='',
        help_text='Error message if generation failed.',
    )
    
    # --- Timestamps ---
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    started_at = models.DateTimeField(blank=True, null=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    
    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['story', '-created_at']),
            models.Index(fields=['status']),
            models.Index(fields=['luma_job_id']),
        ]
    
    def __str__(self):
        return f'Video Job {self.id}: {self.story.title} ({self.status})'
    
    @property
    def is_ready(self):
        return self.status == self.Status.COMPLETED and self.video_url
    
    @property
    def is_processing(self):
        return self.status in (self.Status.PENDING, self.Status.PROCESSING)


class AudioNarrationJob(models.Model):
    """Track text-to-speech narration jobs."""
    
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'
    
    # --- Ownership ---
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='audio_jobs',
    )
    story = models.ForeignKey(
        'stories.Story',
        on_delete=models.CASCADE,
        related_name='audio_narrations',
        null=True,
        blank=True,
        help_text='Story being narrated (story-based narrations).',
    )
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        on_delete=models.CASCADE,
        related_name='audio_narrations',
        null=True,
        blank=True,
        help_text='Artifact whose story is narrated (audio guide).',
    )

    # --- TTS details ---
    narration_text = models.TextField(
        blank=True,
        default='',
        help_text='Snapshot of the text that was converted to speech.',
    )
    voice_id = models.CharField(
        max_length=100,
        blank=True,
        default='default',
        help_text='Voice ID for TTS provider.',
    )
    language = models.CharField(
        max_length=10,
        default='en',
        help_text='Language code for narration.',
    )
    speed = models.FloatField(
        default=1.0,
        help_text='Playback speed multiplier.',
    )
    
    # --- Status ---
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
    )
    
    # --- Output ---
    audio_file = models.FileField(
        upload_to='audio/narrations/',
        blank=True,
        help_text='Generated audio file (MP3).',
    )
    audio_url = models.URLField(
        blank=True,
        default='',
        help_text='Legacy URL to the generated audio (kept for compatibility).',
    )
    duration = models.PositiveIntegerField(
        default=0,
        help_text='Audio duration in seconds.',
    )
    file_size = models.PositiveIntegerField(
        default=0,
        help_text='Audio file size in bytes.',
    )
    error_message = models.TextField(
        blank=True,
        default='',
        help_text='Error message if narration failed.',
    )
    
    # --- Timestamps ---
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    
    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['story', '-created_at']),
            models.Index(fields=['status']),
        ]
    
    def __str__(self):
        if self.story_id:
            title = self.story.title
        elif self.artifact_id:
            title = self.artifact.title
        else:
            title = 'Narration'
        return f'Audio Job {self.id}: {title} ({self.status})'
    
    @property
    def is_ready(self):
        return self.status == self.Status.COMPLETED and self.audio_url