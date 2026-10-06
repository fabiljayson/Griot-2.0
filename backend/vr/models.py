"""VR domain models for the Griot AI Unity application.

The VR layer is a *view* onto content that already exists. A `VRExperience`
places existing `qr_codes.Artifact` rows in a Unity scene, and points at
narration jobs `media_app` already produces. Nothing about an artifact is copied
into this app: duplicating a title, a description or a story would create two
answers to "what is this object called" and the museum would eventually be
showing the stale one.

Two things here are security-relevant, and both are deliberate:

* `VRLaunchToken` stores a SHA-256 *hash* of the launch token — never the token
  itself. That token is a bearer credential travelling through an Android
  intent, a channel any app on the device can observe or forge, so a leaked
  database must not hand out working credentials.
* `VRSession` is the row progress is recorded against, and it can award XP at
  most once no matter how many times a client posts `complete`.
"""

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.utils.text import slugify
from django.utils.translation import gettext_lazy as _

from stories.models import Story


class VRExperience(models.Model):
    """A VR scene a reader can be launched into.

    `scene_identifier` is what Unity loads (`SceneManager.LoadScene`), so it is
    unique: two experiences pointing at one scene would make "which experience
    am I in" unanswerable as soon as the scene reports progress back.

    `architecture` note — the fields mirroring `qr_codes.Artifact`
    (`museum_name`, `region`, `culture`) are `CharField`s for the same reason
    they are there: this project has no `Museum`/`Region` tables, and inventing
    them for VR alone would fork the data model.
    """

    title = models.CharField(max_length=200)
    slug = models.SlugField(max_length=250, unique=True, blank=True)
    description = models.TextField(
        blank=True,
        default='',
        help_text='Shown as the experience summary in Flutter and the loading screen.',
    )
    thumbnail = models.ImageField(
        upload_to='vr/thumbnails/',
        blank=True,
        null=True,
        help_text='Cover image for the experience card.',
    )

    # --- What Unity loads ---
    scene_identifier = models.CharField(
        max_length=100,
        unique=True,
        help_text='Unity scene name or addressable key (e.g. bamoun_gallery).',
    )
    environment = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='Environment prefab identifier inside the Unity project.',
    )

    # --- Cultural metadata (mirrors Artifact, so the two read alike) ---
    language = models.CharField(
        max_length=10,
        choices=Story.Language.choices,
        default=Story.Language.ENGLISH,
        help_text='Primary narration language of the experience.',
    )
    museum_name = models.CharField(max_length=200, blank=True, default='')
    region = models.CharField(max_length=100, blank=True, default='')
    culture = models.CharField(max_length=200, blank=True, default='')

    artifacts = models.ManyToManyField(
        'qr_codes.Artifact',
        through='VRExperienceArtifact',
        related_name='vr_experiences',
        blank=True,
        help_text='Artifacts placed in this experience.',
    )

    # Defaults to inactive: a scene that exists in the database but not yet in
    # a shipped Unity build must not be launchable, and the safe default is the
    # one a curator gets without thinking about it.
    is_active = models.BooleanField(
        default=False,
        help_text='Whether readers can be launched into this experience.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'VR experience'
        verbose_name_plural = 'VR experiences'
        indexes = [
            models.Index(fields=['is_active']),
            models.Index(fields=['slug']),
        ]

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.title)
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.title} ({self.scene_identifier})'


class VRExperienceArtifact(models.Model):
    """One artifact as placed inside one experience.

    A through model rather than a plain `ManyToManyField` because the placement
    itself carries data Unity needs: where the 3D model lives, how big it is,
    whether it can be picked up, and which narration belongs to it.
    """

    experience = models.ForeignKey(
        VRExperience,
        on_delete=models.CASCADE,
        related_name='placements',
    )
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        on_delete=models.CASCADE,
        related_name='vr_placements',
    )

    order = models.PositiveSmallIntegerField(
        default=0,
        help_text='Display order inside the scene.',
    )
    model_url = models.URLField(
        blank=True,
        default='',
        help_text='3D asset (glTF/GLB) URL or media path. Empty = placeholder mesh.',
    )
    model_scale = models.FloatField(
        default=1.0,
        help_text='Scale Unity applies to the loaded model.',
    )
    is_interactive = models.BooleanField(
        default=True,
        help_text='Whether the reader can select and inspect this artifact.',
    )
    narration = models.ForeignKey(
        'media_app.AudioNarrationJob',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='vr_placements',
        help_text='Pre-generated narration replayed in VR. Reuses the TTS pipeline.',
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['order', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['experience', 'artifact'],
                name='uniq_vr_placement',
            ),
        ]

    def __str__(self):
        return f'{self.artifact} in {self.experience}'


class VRLaunchToken(models.Model):
    """A single-use, short-lived credential that hands a session to Unity.

    Why a dedicated token instead of a JWT in the deep link: the link is built
    by the phone, delivered by Android, and readable by any app that registers
    the scheme. A long-lived token in that channel is a stolen account. This one
    is worth almost nothing to an attacker — it expires in seconds, works once,
    is bound to the user who asked for it, and only opens one experience.

    Only the hash is stored. `token_hash` is unique so a duplicate cannot be
    inserted, and consumption is an atomic conditional UPDATE so two concurrent
    exchanges cannot both succeed.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='vr_launch_tokens',
    )
    experience = models.ForeignKey(
        VRExperience,
        on_delete=models.CASCADE,
        related_name='launch_tokens',
    )
    artifact = models.ForeignKey(
        'qr_codes.Artifact',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='vr_launch_tokens',
        help_text='Artifact the reader tapped, when they came from an artifact page.',
    )

    token_hash = models.CharField(
        max_length=64,
        unique=True,
        help_text='SHA-256 hex digest of the launch token. Never the token itself.',
    )
    expires_at = models.DateTimeField(db_index=True)
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['expires_at', 'used_at']),
        ]

    @property
    def is_expired(self) -> bool:
        return self.expires_at <= timezone.now()

    @property
    def is_usable(self) -> bool:
        return self.used_at is None and not self.is_expired

    def __str__(self):
        state = 'used' if self.used_at else ('expired' if self.is_expired else 'valid')
        return f'VR launch token for {self.user} ({state})'


class VRSession(models.Model):
    """One reader's visit to one experience.

    Created when a launch token is exchanged, closed by
    `POST /api/vr/sessions/<id>/complete/`. `xp_awarded` is a column rather than
    a derived value so completing twice is provably idempotent: the second call
    sees the XP already paid and awards none.
    """

    class Status(models.TextChoices):
        ACTIVE = 'active', _('Active')
        COMPLETED = 'completed', _('Completed')
        ABANDONED = 'abandoned', _('Abandoned')

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='vr_sessions',
    )
    experience = models.ForeignKey(
        VRExperience,
        on_delete=models.CASCADE,
        related_name='sessions',
    )
    launch_token = models.ForeignKey(
        VRLaunchToken,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='sessions',
    )

    # --- Lifecycle ---
    start_time = models.DateTimeField(auto_now_add=True)
    end_time = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(default=0)
    completion_status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.ACTIVE,
        db_index=True,
    )

    # --- Progress ---
    progress = models.FloatField(
        default=0.0,
        help_text='Fraction of the experience completed, 0.0–1.0.',
    )
    artifacts_viewed = models.ManyToManyField(
        'qr_codes.Artifact',
        blank=True,
        related_name='vr_sessions',
        help_text='Artifacts the reader actually opened. Validated against the experience.',
    )
    xp_awarded = models.PositiveIntegerField(
        default=0,
        help_text='XP paid out for this session. Set once; guards against double awards.',
    )

    # --- Diagnostics ---
    device_model = models.CharField(
        max_length=120,
        blank=True,
        default='',
        help_text='Headset/device the exchange came from, for support.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-start_time']
        verbose_name = 'VR session'
        verbose_name_plural = 'VR sessions'
        indexes = [
            models.Index(fields=['user', '-start_time']),
            models.Index(fields=['experience', '-start_time']),
            models.Index(fields=['completion_status']),
        ]

    @property
    def is_active(self) -> bool:
        return self.completion_status == self.Status.ACTIVE

    def __str__(self):
        return f'{self.user} → {self.experience} ({self.completion_status})'


# Module-level choice alias — see the note in stories/models.py. drf-spectacular
# resolves ENUM_NAME_OVERRIDES with `import_string`, which cannot walk into a
# nested class, so the name is pinned here and referenced from settings.
VRCompletionStatusChoices = VRSession.Status
