from django.conf import settings
from django.db import models


class MediaOriginKind(models.TextChoices):
    """Whether a media artifact was machine-generated or recorded by a person.

    Module-level because both job models use it and drf-spectacular needs an
    importable path for ENUM_NAME_OVERRIDES (see the note at the bottom of this
    file).
    """

    SYNTHETIC = 'synthetic', 'AI-generated from the story text'
    HUMAN_RECORDING = 'human_recording', 'Recorded by a human narrator'


def normalise_engine(service, medium: str = 'narration') -> str:
    """Read a service's declared engine name into a storable string.

    A narration service that forgets to declare ``engine`` must not fail the
    create with a database error or an AttributeError — the job is still worth
    recording, it just gets an honest "unknown" credit instead of a fabricated
    one. Anything non-string (a test double, a future enum) lands in the same
    place, which is the point: we would rather say nothing than guess.
    """
    engine = getattr(service, 'engine', None)
    if not isinstance(engine, str):
        return f'unknown-{medium}-engine'
    engine = engine.strip()
    if not engine:
        return f'unknown-{medium}-engine'
    # The column is max_length=40; truncating beats a 500 on a long vendor name.
    return engine[:40]


def _media_attribution(kind: str, engine: str, medium: str) -> str:
    """Credit line for a media artifact, e.g. "AI-generated narration (gTTS)".

    Shared by both job models so an audio guide and a video can never word their
    synthetic disclosure differently.
    """
    if kind == MediaOriginKind.HUMAN_RECORDING:
        return f'Recorded {medium} by a human narrator'
    engine = engine or 'an unnamed model'
    if engine.startswith('unknown-'):
        return f'{medium} of unrecorded origin'
    return f'AI-generated {medium} ({engine})'


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
    # The provider's URL points at its own CDN and is not ours to rely on
    # forever. On completion the bytes are pulled down into this field — the
    # same contract AudioNarrationJob.audio_file already keeps for narration —
    # so playback keeps working after the provider link expires, and the
    # render is never paid for twice just to retrieve it.
    video_file = models.FileField(
        upload_to='video/generations/',
        blank=True,
        help_text='Stored copy of the generated video (downloaded on completion).',
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

    # --- Provenance ---
    # A Luma render of an oral tradition is a modern AI illustration of it.
    # Recording that on the job (rather than inferring it from the URL) is what
    # lets the player label it "AI-generated" instead of passing it off as
    # archival footage of the community.
    origin_kind = models.CharField(
        max_length=30,
        choices=MediaOriginKind.choices,
        default=MediaOriginKind.SYNTHETIC,
        help_text='Whether the video was AI-generated or human-recorded.',
    )
    engine = models.CharField(
        max_length=40,
        blank=True,
        default='',
        help_text='Name/version of the generating model (e.g. luma-dream-machine).',
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

    @property
    def is_synthetic(self) -> bool:
        """True when a model generated this video, not a human camera."""
        return self.origin_kind == MediaOriginKind.SYNTHETIC

    @property
    def attribution(self) -> str:
        """Credit line describing what produced this video."""
        return _media_attribution(self.origin_kind, self.engine, 'video')


class AudioNarrationJob(models.Model):
    """Track text-to-speech narration jobs.

    ``target_key`` is a denormalised, never-NULL identifier for what the job
    narrates. It exists because a unique index over ``(story, artifact)`` does
    not work here: both columns are nullable, and SQLite — like standard SQL —
    treats NULLs as distinct from one another, so two identical story-only jobs
    sail straight through the constraint. Nearly every job is story-only or
    artifact-only, so that constraint protected almost nothing while looking
    like it worked. Keying on a non-null column is the only version that
    actually holds.
    """
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

    # --- Provenance ---
    # gTTS speaks the story's words; no member of the community ever performed
    # it. The engine and the synthetic flag are stored on the job so a listener
    # is told what they are hearing instead of assuming a recorded elder.
    origin_kind = models.CharField(
        max_length=30,
        choices=MediaOriginKind.choices,
        default=MediaOriginKind.SYNTHETIC,
        help_text='Whether the audio was AI-generated or human-recorded.',
    )
    engine = models.CharField(
        max_length=40,
        blank=True,
        default='',
        help_text='Name/version of the TTS engine (e.g. gtts).',
    )
    reviewed_by_source = models.BooleanField(
        default=False,
        help_text='A source community member reviewed and approved this narration.',
    )
    target_key = models.CharField(
        max_length=40,
        editable=False,
        default='',
        help_text='Non-null identity of the narrated target (see build_target_key).',
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
        constraints = [
            # At most one completed job per target and language.
            #
            # The narration endpoints all ask "does a completed job already
            # exist for this story?" before generating, which is a
            # check-then-act: two concurrent requests both see "no" and both
            # generate, storing duplicate audio and burning a paid TTS call
            # each. A conditional unique index closes the window at the
            # database, so the loser gets an IntegrityError instead of a
            # duplicate row.
            #
            # Keyed on `target_key` rather than `(story, artifact)` — see the
            # class docstring for why the nullable columns do not work.
            #
            # Partial (`status='completed'`) so a failed attempt can be retried
            # without deleting the failure first: pending/processing/failed
            # rows are attempts, and only a result is worth deduplicating.
            models.UniqueConstraint(
                fields=['target_key', 'language'],
                condition=models.Q(status='completed'),
                name='uniq_completed_narration_per_target_language',
            ),
        ]
    
    def __str__(self):
        if self.story_id:
            title = self.story.title
        elif self.artifact_id:
            title = self.artifact.title
        else:
            title = 'Narration'
        return f'Audio Job {self.id}: {title} ({self.status})'
    
    @staticmethod
    def build_target_key(story_id, artifact_id) -> str:
        """Non-null identity of a narration target.

        Prefixed so a story and an artifact with the same numeric id cannot
        collide. A job with neither target gets its own key, so the uniqueness
        guarantee still applies (one completed orphan job) rather than every
        such job colliding on ''.
        """
        if story_id and artifact_id:
            return f'both:{story_id}:{artifact_id}'
        if story_id:
            return f'story:{story_id}'
        if artifact_id:
            return f'artifact:{artifact_id}'
        return 'none'

    def save(self, *args, **kwargs):
        # Recomputed on every write so it cannot drift from the FKs.
        self.target_key = self.build_target_key(self.story_id, self.artifact_id)
        if kwargs.get('update_fields') is not None:
            kwargs['update_fields'] = set(kwargs['update_fields']) | {'target_key'}
        super().save(*args, **kwargs)

    @property
    def is_ready(self):
        return self.status == self.Status.COMPLETED and self.audio_url

    @property
    def is_synthetic(self) -> bool:
        """True when a TTS model produced this audio, not a human narrator."""
        return self.origin_kind == MediaOriginKind.SYNTHETIC

    @property
    def attribution(self) -> str:
        """Credit line describing what produced this audio."""
        line = _media_attribution(self.origin_kind, self.engine, 'narration')
        if self.reviewed_by_source:
            line += ' · reviewed by the source community'
        return line

# Module-level choice aliases — see the note in stories/models.py.
#
# Note that VideoGenerationJob.Status and AudioNarrationJob.Status have
# identical values, so they share ONE override name. drf-spectacular errors on
# two names pointing at the same choice set, and rightly so: publishing the
# identical enum twice under different names would imply they could diverge.
MediaJobStatusChoices = VideoGenerationJob.Status
MediaOriginKindChoices = MediaOriginKind
