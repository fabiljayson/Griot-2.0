"""
Artifact model with automated QR code generation.

When an artifact is created or updated, a QR code PNG is automatically
generated encoding the artifact's detail URL and saved to the qr_code field.
"""

import io
import os

from django.conf import settings
from django.db import models
from django.utils.text import slugify
import qrcode
from qrcode.image.styledpil import StyledPilImage
from qrcode.image.styles.moduledrawers import RoundedModuleDrawer
from PIL import Image


class Artifact(models.Model):
    """
    A cultural artifact with story, media, and auto-generated QR code.
    
    When saved, automatically generates a high-quality QR code PNG
    linking to the artifact's mobile-optimized detail page.
    """

    CATEGORY_CHOICES = [
        ('kingdom', 'Kingdom'),
        ('landmark', 'Landmark'),
        ('artifact', 'Artifact'),
        ('legend', 'Legend'),
        ('culture', 'Culture'),
    ]

    title = models.CharField(
        max_length=200,
        help_text='Name of the artifact.',
    )
    slug = models.SlugField(
        max_length=250,
        unique=True,
        blank=True,
        help_text='URL-friendly identifier (auto-generated from title).',
    )
    category = models.CharField(
        max_length=20,
        choices=CATEGORY_CHOICES,
        default='culture',
        help_text='Classification: Kingdom, Landmark, Artifact, Legend, or Culture.',
    )
    location = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='City or region (e.g., Foumban, West Region).',
    )
    story = models.TextField(
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
    video_url = models.URLField(
        blank=True,
        null=True,
        help_text='Optional YouTube/Vimeo video URL.',
    )
    qr_code = models.ImageField(
        upload_to='qr_codes/',
        editable=False,
        blank=True,
        null=True,
        help_text='Auto-generated QR code linking to this artifact.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Artifact'
        verbose_name_plural = 'Artifacts'

    def __str__(self):
        return self.title

    def save(self, *args, **kwargs):
        # Auto-generate slug from title
        if not self.slug:
            self.slug = slugify(self.title)
            # Ensure uniqueness
            original_slug = self.slug
            counter = 1
            while Artifact.objects.filter(slug=self.slug).exclude(pk=self.pk).exists():
                self.slug = f'{original_slug}-{counter}'
                counter += 1

        # Generate QR code before saving
        super().save(*args, **kwargs)

        # Only generate QR if we don't have one yet or if slug changed
        if not self.qr_code or self.has_changed('slug'):
            self._generate_qr_code()

    def has_changed(self, field_name):
        """Check if a field has changed since last save."""
        if not self.pk:
            return True
        try:
            old_instance = Artifact.objects.get(pk=self.pk)
            return getattr(self, field_name) != getattr(old_instance, field_name)
        except Artifact.DoesNotExist:
            return True

    def _generate_qr_code(self):
        """Generate a high-quality QR code PNG and save it to the qr_code field."""
        # Build the target URL
        site_url = getattr(settings, 'SITE_URL', 'https://africanteller.org')
        target_url = f'{site_url}/artifacts/{self.slug}/'

        # Create QR code with styling
        qr = qrcode.QRCode(
            version=None,  # Auto-size based on data
            error_correction=qrcode.constants.ERROR_CORRECT_H,  # 30% recovery
            box_size=10,
            border=4,
        )
        qr.add_data(target_url)
        qr.make(fit=True)

        # Generate styled image with rounded modules
        try:
            img = qr.make_image(
                image_factory=StyledPilImage,
                module_drawer=RoundedModuleDrawer(),
                fill_color='#C85A32',  # Terracotta brand color
                back_color='#FFFFFF',
            )
        except Exception:
            # Fallback to standard QR code if styled generation fails
            img = qr.make_image(
                fill_color='#C85A32',
                back_color='#FFFFFF',
            )

        # Convert to RGB if needed (for PNG compatibility)
        if img.mode != 'RGB':
            img = img.convert('RGB')

        # Save to buffer
        buffer = io.BytesIO()
        img.save(buffer, format='PNG', quality=95)
        buffer.seek(0)

        # Generate filename
        filename = f'{self.slug}-qr.png'

        # Save to model field
        self.qr_code.save(filename, buffer, save=False)
        self.save(update_fields=['qr_code'])

    @property
    def qr_code_url(self):
        """Return the URL of the QR code image."""
        if self.qr_code:
            return self.qr_code.url
        return None

    @property
    def detail_url(self):
        """Return the full URL to this artifact's detail page."""
        site_url = getattr(settings, 'SITE_URL', 'https://africanteller.org')
        return f'{site_url}/artifacts/{self.slug}/'
