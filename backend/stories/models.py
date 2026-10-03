from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils.text import slugify


class StoryCategory(models.Model):
    """Category for organizing stories (e.g., Folktales, History, Proverbs)."""

    name = models.CharField(max_length=100, unique=True)
    slug = models.SlugField(max_length=120, unique=True, blank=True)
    description = models.TextField(blank=True, default='')
    icon = models.CharField(max_length=10, blank=True, default='📖')
    color = models.CharField(max_length=7, blank=True, default='#8B4513')  # Hex color
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name_plural = 'Story categories'
        ordering = ['name']

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.name)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.name


class Story(models.Model):
    """A cultural story, tale, or oral tradition entry.

    Stories can be submitted by Contributors and managed by Institution Managers.
    Each story includes rich content, metadata, and optional media attachments.
    """

    class Status(models.TextChoices):
        DRAFT = 'draft', 'Draft'
        PENDING = 'pending', 'Pending Review'
        PUBLISHED = 'published', 'Published'
        REJECTED = 'rejected', 'Rejected'
        ARCHIVED = 'archived', 'Archived'

    class Language(models.TextChoices):
        ENGLISH = 'en', 'English'
        FRENCH = 'fr', 'French'
        FULA = 'ful', 'Fula'
        DUALA = 'dua', 'Duala'
        EWONDO = 'ewo', 'Ewondo'
        BAMILEKE = 'bml', 'Bamileke'
        OTHER = 'other', 'Other'

    class Origin(models.TextChoices):
        """Where a story's text came from, before it entered this database.

        The app renders oral traditions it did not record. Distinguishing a
        community recording from a researcher's transcription, and both from
        seeded demo content, is what lets a reader trust the label on the page.
        """

        COMMUNITY_RECORDED = 'community_recorded', 'Recorded from a community member'
        ORAL_TRANSCRIPTION = 'oral_transcription', 'Transcribed from an oral telling'
        PUBLISHED_COLLECTION = 'published_collection', 'From a published collection'
        CONTRIBUTOR_ORIGINAL = 'contributor_original', 'Original contribution'
        SEEDED = 'seeded', 'Seeded demonstration content'
        UNKNOWN = 'unknown', 'Unknown'

    class Consent(models.TextChoices):
        """Whether the people behind the story agreed to its publication."""

        NOT_REQUESTED = 'not_requested', 'Consent not yet requested'
        PENDING = 'pending', 'Consent pending'
        GRANTED = 'granted', 'Consent granted'
        GRANTED_RESTRICTED = 'granted_restricted', 'Consent granted with restrictions'
        WITHHELD = 'withheld', 'Consent withheld'

    class Licence(models.TextChoices):
        """Rights under which the text is shared."""

        ALL_RIGHTS_RESERVED = 'all_rights_reserved', 'All rights reserved'
        CC_BY = 'cc_by', 'CC BY 4.0'
        CC_BY_SA = 'cc_by_sa', 'CC BY-SA 4.0'
        CC_BY_NC = 'cc_by_nc', 'CC BY-NC 4.0'
        CC_BY_NC_SA = 'cc_by_nc_sa', 'CC BY-NC-SA 4.0'
        PUBLIC_DOMAIN = 'public_domain', 'Public domain'
        UNDETERMINED = 'undetermined', 'Undetermined'

    # --- Core fields ---
    title = models.CharField(max_length=200)
    slug = models.SlugField(max_length=250, unique=True, blank=True)
    content = models.TextField(help_text='Story content in Markdown format.')
    summary = models.TextField(
        max_length=500,
        blank=True,
        default='',
        help_text='Brief summary for previews (max 500 chars).',
    )

    # --- Author & ownership ---
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='authored_stories',
    )
    co_authors = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        blank=True,
        related_name='co_authored_stories',
    )

    # --- Classification ---
    categories = models.ManyToManyField(StoryCategory, blank=True, related_name='stories')
    language = models.CharField(
        max_length=10,
        choices=Language.choices,
        default=Language.ENGLISH,
    )
    region = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='Geographic origin of the story (e.g., Northwest Region).',
    )
    tags = models.CharField(
        max_length=500,
        blank=True,
        default='',
        help_text='Comma-separated tags for search and filtering.',
    )

    # --- Media ---
    cover_image = models.ImageField(
        upload_to='stories/covers/',
        blank=True,
        null=True,
        help_text='Cover image for the story.',
    )
    cover_image_blurhash = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='BlurHash placeholder for progressive image loading.',
    )
    audio_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to audio narration (Phase 4: TTS/voice).',
    )
    video_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to AI-generated video (Phase 4: Luma AI).',
    )

    # --- Metadata ---
    cultural_context = models.TextField(
        blank=True,
        default='',
        help_text='Historical and cultural context for the story.',
    )
    moral_lesson = models.TextField(
        blank=True,
        default='',
        help_text='Key moral or teaching from the story.',
    )
    source = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Original source or teller of the story.',
    )
    estimated_read_time = models.PositiveIntegerField(
        default=0,
        help_text='Estimated read time in minutes.',
    )

    # --- Provenance & rights ---
    # A story is a rendering of someone's tradition, not our property. These
    # fields are editable rather than derived so that a reviewer correcting a
    # provenance record is a normal, auditable write.
    origin = models.CharField(
        max_length=30,
        choices=Origin.choices,
        default=Origin.UNKNOWN,
        help_text='Where this text came from, independently of `source`.',
    )
    provenance_notes = models.TextField(
        blank=True,
        default='',
        help_text='How this version was obtained (interview, archive, memory).',
    )
    consent_status = models.CharField(
        max_length=30,
        choices=Consent.choices,
        default=Consent.NOT_REQUESTED,
        help_text='Whether the source community agreed to this publication.',
    )
    rights_holder = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Person or community holding the rights to this tradition.',
    )
    licence = models.CharField(
        max_length=30,
        choices=Licence.choices,
        default=Licence.UNDETERMINED,
        help_text='Licence the text is shared under.',
    )
    recorded_at = models.DateField(
        blank=True,
        null=True,
        help_text='When the story was recorded from its source, if it was.',
    )

    # --- Status & moderation ---
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.DRAFT,
    )
    reviewer_notes = models.TextField(
        blank=True,
        default='',
        help_text='Internal notes from the reviewer.',
    )

    # --- Stats ---
    view_count = models.PositiveIntegerField(default=0)
    like_count = models.PositiveIntegerField(default=0)
    bookmark_count = models.PositiveIntegerField(default=0)
    share_count = models.PositiveIntegerField(default=0)

    # --- Timestamps ---
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    published_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['-created_at']),
            models.Index(fields=['status', '-published_at']),
            models.Index(fields=['author']),
            models.Index(fields=['language']),
        ]

    def save(self, *args, **kwargs):
        # Publishing a story whose community withheld consent would be the one
        # irreversible cultural-data failure this app must not allow, so it is
        # blocked at the model rather than in each of the four call sites that
        # can set a status (API serializer, web form, seeder, tests).
        if (
            self.status == self.Status.PUBLISHED
            and self.consent_status == self.Consent.WITHHELD
        ):
            raise ValidationError(
                {
                    'consent_status': (
                        'Consent is withheld for this story, so it cannot be '
                        'published. Change the consent status first.'
                    ),
                },
            )
        if not self.slug:
            self.slug = slugify(self.title)
        # Auto-calculate read time (~200 words per minute)
        if not self.estimated_read_time and self.content:
            word_count = len(self.content.split())
            self.estimated_read_time = max(1, word_count // 200)
        super().save(*args, **kwargs)
        # Auto-resize and generate BlurHash placeholder for the cover image
        if self.cover_image:
            from media_app.services.blurhash_utils import generate_blurhash, resize_image
            resize_image(self.cover_image)
            if not self.cover_image_blurhash:
                blurhash_str = generate_blurhash(self.cover_image)
                if blurhash_str:
                    Story.objects.filter(pk=self.pk).update(cover_image_blurhash=blurhash_str)
                    self.cover_image_blurhash = blurhash_str

    def __str__(self):
        return self.title

    @property
    def is_published(self):
        return self.status == self.Status.PUBLISHED

    @property
    def tag_list(self):
        """Return tags as a list."""
        if not self.tags:
            return []
        return [tag.strip() for tag in self.tags.split(',') if tag.strip()]

    @property
    def is_synthetic_origin(self) -> bool:
        """True when this text was generated or seeded, not sourced from a community.

        Surfaces the "this is demo content" label on the web and in the API so
        seeded stories can never be mistaken for recorded oral tradition.
        """
        return self.origin == self.Origin.SEEDED

    @property
    def attribution(self) -> str:
        """One-line credit shown under the story, combining the fields we have.

        Deliberately derived rather than stored: it must never drift from
        ``source``/``rights_holder``, and a free-text attribution field would
        drift by definition.
        """
        parts = []
        if self.source:
            parts.append(f'Told by {self.source}' if self.origin != self.Origin.SEEDED else self.source)
        if self.rights_holder and self.rights_holder != self.source:
            parts.append(f'Rights: {self.rights_holder}')
        if not parts and self.region:
            parts.append(self.region)
        return ' · '.join(parts)


class StoryBookmark(models.Model):
    """User's saved/bookmarked stories."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='story_bookmarks',
    )
    story = models.ForeignKey(
        Story,
        on_delete=models.CASCADE,
        related_name='bookmarks',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    note = models.TextField(
        blank=True,
        default='',
        help_text='Personal note about why this story was saved.',
    )

    class Meta:
        unique_together = ('user', 'story')
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.user.username} bookmarked {self.story.title}'


class StoryLike(models.Model):
    """User's likes/favorites on stories."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='story_likes',
    )
    story = models.ForeignKey(
        Story,
        on_delete=models.CASCADE,
        related_name='likes',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'story')

    def __str__(self):
        return f'{self.user.username} likes {self.story.title}'


class StoryFlag(models.Model):
    """User reports/flags for cultural inaccuracy or inappropriate content."""

    class Reason(models.TextChoices):
        CULTURAL_INACCURACY = 'cultural_inaccuracy', 'Cultural Inaccuracy'
        INAPPROPRIATE_CONTENT = 'inappropriate_content', 'Inappropriate Content'
        COPYRIGHT_VIOLATION = 'copyright_violation', 'Copyright Violation'
        WRONG_CATEGORY = 'wrong_category', 'Wrong Category'
        OTHER = 'other', 'Other'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='story_flags',
    )
    story = models.ForeignKey(
        Story,
        on_delete=models.CASCADE,
        related_name='flags',
    )
    reason = models.CharField(max_length=30, choices=Reason.choices)
    details = models.TextField(
        blank=True,
        default='',
        help_text='Additional details about the flag.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    resolved = models.BooleanField(default=False)
    resolution_notes = models.TextField(blank=True, default='')

    class Meta:
        unique_together = ('user', 'story')
        ordering = ['-created_at']

    def __str__(self):
        return f'Flag: {self.story.title} - {self.get_reason_display()}'


class ReadingProgress(models.Model):
    """Track user's reading progress through stories."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='reading_progress',
    )
    story = models.ForeignKey(
        Story,
        on_delete=models.CASCADE,
        related_name='reading_progress',
    )
    progress_percent = models.PositiveIntegerField(
        default=0,
        help_text='Reading progress as percentage (0-100).',
    )
    last_read_position = models.PositiveIntegerField(
        default=0,
        help_text='Last scroll position or character index.',
    )
    completed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'story')
        ordering = ['-updated_at']

    def __str__(self):
        return f'{self.user.username} reading {self.story.title} ({self.progress_percent}%)'

    @property
    def is_complete(self):
        return self.progress_percent >= 100 or self.completed


class StoryShare(models.Model):
    """Track story shares for analytics."""

    PLATFORM_CHOICES = [
        ('twitter', 'Twitter'),
        ('facebook', 'Facebook'),
        ('whatsapp', 'WhatsApp'),
        ('telegram', 'Telegram'),
        ('link', 'Copy Link'),
        ('other', 'Other'),
    ]

    story = models.ForeignKey(
        Story,
        on_delete=models.CASCADE,
        related_name='shares',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='story_shares',
    )
    platform = models.CharField(
        max_length=20,
        choices=PLATFORM_CHOICES,
        default='other',
    )
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['story', '-created_at']),
            models.Index(fields=['platform']),
        ]

    def __str__(self):
        return f'Share: {self.story.title} via {self.platform}'

# ---------------------------------------------------------------------------
# Module-level choice aliases
# ---------------------------------------------------------------------------
# Several models across this project each define a nested `Status` or
# `Category` TextChoices, so drf-spectacular cannot derive a unique schema
# component name from the field alone and falls back to hash-suffixed names
# like "Status244Enum". `ENUM_NAME_OVERRIDES` fixes that, but it resolves each
# value with `import_string`, which cannot walk *into* a class
# (`stories.models.Story.Status.choices` fails — it tries to import a module
# named `stories.models.Story`). Re-exporting the nested enum at module level
# gives the override a path that actually resolves.
#
# The alias, not the nested class, is the canonical name; keep them together.
StoryStatusChoices = Story.Status
StoryOriginChoices = Story.Origin
StoryConsentChoices = Story.Consent
StoryLicenceChoices = Story.Licence
