"""
Image utilities for uploaded files: BlurHash generation and auto-resize.

Usage in models:
    from media_app.services.blurhash_utils import generate_blurhash, resize_image
    blurhash = generate_blurhash(image_field)
    resize_image(image_field, max_width=1200, max_height=900)
"""

import io
import logging

from PIL import Image

logger = logging.getLogger(__name__)

# Default max dimensions for uploaded images
DEFAULT_MAX_WIDTH = 1200
DEFAULT_MAX_HEIGHT = 900
DEFAULT_JPEG_QUALITY = 85


def resize_image(image_field, max_width=DEFAULT_MAX_WIDTH, max_height=DEFAULT_MAX_HEIGHT, quality=DEFAULT_JPEG_QUALITY):
    """Resize an uploaded image to fit within max dimensions.

    Preserves aspect ratio. Converts to RGB for JPEG output. Only resizes
    if the image exceeds the max dimensions — small images are left alone.

    Args:
        image_field: A Django ImageField or FileField value.
        max_width: Maximum width in pixels.
        max_height: Maximum height in pixels.
        quality: JPEG quality (1-100).

    Returns:
        True if the image was resized, False otherwise.
    """
    if not image_field:
        return False

    try:
        image_field.open('rb')
        img = Image.open(image_field)

        # Skip if already within bounds
        if img.width <= max_width and img.height <= max_height:
            image_field.close()
            return False

        # Resize preserving aspect ratio
        img.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)

        # Convert to RGB for JPEG (handles RGBA, palette, etc.)
        if img.mode != 'RGB':
            img = img.convert('RGB')

        # Save back to the field
        buffer = io.BytesIO()
        img.save(buffer, format='JPEG', quality=quality, optimize=True)
        buffer.seek(0)

        # Determine output filename
        name = image_field.name
        base, _ = name.rsplit('.', 1) if '.' in name else (name, '')
        output_name = f'{base}.jpg'

        image_field.save(output_name, buffer, save=False)
        image_field.close()
        return True
    except Exception:
        logger.exception('Failed to resize image %s', getattr(image_field, 'name', 'unknown'))
        return False


def generate_blurhash(image_field, component_x=4, component_y=3):
    """Generate a BlurHash string from a Django ImageField.

    Args:
        image_field: A Django ImageField value (the file object).
        component_x: Number of horizontal components (4-9 typical).
        component_y: Number of vertical components (3-7 typical).

    Returns:
        A BlurHash string, or empty string if generation fails.
    """
    if not image_field:
        return ''

    try:
        import blurhash
        image_field.open('rb')
        img = Image.open(image_field)
        # Convert to RGB if needed (BlurHash requires RGB)
        if img.mode != 'RGB':
            img = img.convert('RGB')
        # Resize for faster encoding (component count controls quality)
        img.thumbnail((100, 100), Image.Resampling.LANCZOS)
        hash_str = blurhash.encode(img, x_components=component_x, y_components=component_y)
        image_field.close()
        return hash_str
    except Exception:
        logger.exception('Failed to generate BlurHash for %s', image_field.name)
        return ''
