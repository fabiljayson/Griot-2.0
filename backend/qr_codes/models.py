from django.conf import settings
from django.db import models
from django.utils.text import slugify
from django.utils.translation import gettext_lazy as _


class Artifact(models.Model):
    """A museum artifact or cultural object.

    Artifacts are physical items (sculptures, textiles, instruments, etc.)
    that can be displayed in museums. Each artifact can be linked to stories
    and have QR codes generated for visitor engagement.

    Managed by Institution Managers and Admins.
    """

    class Category(models.TextChoices):
        SCULPTURE = 'sculpture', _('Sculpture')
        TEXTILE = 'textile', _('Textile')
        INSTRUMENT = 'instrument', _('Musical Instrument')
        JEWELRY = 'jewelry', _('Jewelry')
        POTTERY = 'pottery', _('Pottery')
        MASK = 'mask', _('Mask')
        WEAPON = 'weapon', _('Weapon')
        FABRIC = 'fabric', _('Woven Fabric')
        TOOL = 'tool', _('Tool')
        OTHER = 'other', _('Other')

    class ContentType(models.TextChoices):
        """What KIND OF THING this is, as opposed to `Category`'s material.

        A carved mask is both `ContentType.ARTIFACT` and `Category.MASK`.
        Forcing both onto one field is why the crawl importer used to collapse
        every row into `Category.OTHER`: the two vocabularies have different
        shapes and no single mapping between them is correct.
        """

        KINGDOM = 'kingdom', _('Kingdom')
        LANDMARK = 'landmark', _('Landmark')
        ARTIFACT = 'artifact', _('Artifact')
        LEGEND = 'legend', _('Legend')
        CULTURE = 'culture', 'Culture'
        # An honest default: the row exists but nothing has classified it yet.
        # Distinguishable from a genuine `Category.OTHER`, which means "we
        # looked and it genuinely doesn't fit".
        UNKNOWN = 'unknown', 'Unclassified'

    # --- Core fields ---
    title = models.CharField(max_length=200)
    slug = models.SlugField(max_length=250, unique=True, blank=True)
    description = models.TextField(
        help_text='Short explanation of what the artifact looks like.',
    )
    category = models.CharField(
        max_length=20,
        choices=Category.choices,
        default=Category.OTHER,
        db_index=True,
    )
    content_type = models.CharField(
        max_length=20,
        choices=ContentType.choices,
        default=ContentType.UNKNOWN,
        db_index=True,
        help_text='What kind of thing this is: kingdom, landmark, artifact, legend, culture.',
    )

    # --- Ownership & creation ---
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name='created_artifacts',
    )

    # --- Cultural metadata ---
    culture = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Cultural group or kingdom (e.g., Bamoun, Bamileke).',
    )
    region = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='Geographic origin (e.g., Northwest Region).',
    )
    estimated_date = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='Estimated creation period (e.g., 19th century).',
    )
    materials = models.CharField(
        max_length=300,
        blank=True,
        default='',
        help_text='Materials used (e.g., bronze, wood, beads).',
    )
    dimensions = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Physical dimensions.',
    )

    # --- Media ---
    image = models.ImageField(
        upload_to='artifacts/images/',
        blank=True,
        null=True,
        help_text='Primary artifact image.',
    )
    image_blurhash = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='BlurHash placeholder for progressive image loading.',
    )
    additional_images = models.JSONField(
        default=list,
        blank=True,
        help_text='List of additional image URLs.',
    )

    # --- QR code ---
    qr_code_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to the generated QR code image.',
    )
    qr_code_svg = models.TextField(
        blank=True,
        default='',
        help_text='SVG content of the QR code for inline display.',
    )
    deep_link_path = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Deep link path (e.g., /artifact/my-artifact-slug).',
    )

    # --- Related stories ---
    stories = models.ManyToManyField(
        'stories.Story',
        blank=True,
        related_name='artifacts',
        help_text='Stories related to this artifact.',
    )

    # --- Location (for museum floor plans) ---
    museum_name = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Museum where this artifact is displayed.',
    )
    floor = models.CharField(
        max_length=50,
        blank=True,
        default='',
        help_text='Floor or level.',
    )
    display_case = models.CharField(
        max_length=50,
        blank=True,
        default='',
        help_text='Display case or exhibit number.',
    )

    # --- Narrative content (merged from artifacts app) ---
    story = models.TextField(
        blank=True,
        default='',
        help_text='Narrative description of the artifact\'s cultural significance.',
    )
    historical_significance = models.TextField(
        blank=True,
        default='',
        help_text='Cultural background or legend details.',
    )
    source_url = models.URLField(
        blank=True,
        default='',
        help_text='Original source URL of the content.',
    )
    audio_file = models.FileField(
        upload_to='audio/',
        blank=True,
        null=True,
        help_text='Optional audio narration file.',
    )
    video_url_field = models.URLField(
        blank=True,
        null=True,
        help_text='Optional YouTube/Vimeo video URL.',
    )

    # --- Status ---
    is_published = models.BooleanField(
        default=False,
        help_text='Whether this artifact is publicly visible.',
    )

    # --- Timestamps ---
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['-created_at']),
            models.Index(fields=['category']),
            models.Index(fields=['culture']),
            models.Index(fields=['is_published']),
            models.Index(fields=['slug']),
        ]

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.title)
        if not self.deep_link_path:
            self.deep_link_path = f'/artifact/{self.slug}'
        super().save(*args, **kwargs)
        # Auto-resize and generate BlurHash placeholder for the artifact image
        if self.image:
            from media_app.services.blurhash_utils import generate_blurhash, resize_image
            resize_image(self.image)
            if not self.image_blurhash:
                blurhash_str = generate_blurhash(self.image)
                if blurhash_str:
                    Artifact.objects.filter(pk=self.pk).update(image_blurhash=blurhash_str)
                    self.image_blurhash = blurhash_str

    def __str__(self):
        return self.title

    @property
    def qr_deep_link(self):
        """Full deep link URL for QR codes."""
        from django.conf import settings
        base_url = getattr(settings, 'DEEP_LINK_BASE_URL', 'https://africanteller.org')
        return f'{base_url}{self.deep_link_path}'


class QRCodeScan(models.Model):
    """Track QR code scans for analytics and engagement."""

    artifact = models.ForeignKey(
        Artifact,
        on_delete=models.CASCADE,
        related_name='scans',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='qr_scans',
    )

    # Scan metadata
    device_type = models.CharField(
        max_length=50,
        blank=True,
        default='',
        help_text='Device type (iOS, Android, Web).',
    )
    ip_address = models.GenericIPAddressField(
        null=True,
        blank=True,
    )
    user_agent = models.TextField(
        blank=True,
        default='',
    )

    # Location (optional, from device GPS)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['artifact', '-created_at']),
            models.Index(fields=['user', '-created_at']),
        ]

    def __str__(self):
        user_str = self.user.username if self.user else 'Anonymous'
        return f'{user_str} scanned {self.artifact.title}'


# Module-level choice alias — see the note in stories/models.py.
ArtifactCategoryChoices = Artifact.Category
