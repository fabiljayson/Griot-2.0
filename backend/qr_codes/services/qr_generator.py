"""
QR code generation service for museum artifacts.

Generates QR codes that link to artifact detail pages.
Supports PNG and SVG output formats.

`generate_artifact_qr` is the one place that knows what generating a QR code
*means* — which formats exist, which one is persisted, and what the deep link
encodes. The API endpoint and the web admin dashboard both call it. It was
inline in the API view until Phase 5, which meant the rules existed once and
had to be copied to be used anywhere else — the same drift the project has
already paid for twice (`resolve_status`, `resolve_ui_language`).
"""
import io

import qrcode
import segno

# The formats a caller may ask for, and the one whose output is stored on the
# artifact. Only SVG is persisted, because it is the only one that survives
# being handed to a museum to print; PNG and data-uri are responses.
QR_FORMATS = ('svg', 'png', 'data_uri')
PERSISTED_FORMAT = 'svg'

DEFAULT_FOREGROUND = '#C85A32'
DEFAULT_BACKGROUND = '#FFFFFF'


class QRCodeGenerator:
    """Generate QR codes for artifact deep links."""

    # Default QR code styling
    DEFAULT_BOX_SIZE = 10
    DEFAULT_BORDER = 4
    DEFAULT_ERROR_CORRECTION = qrcode.constants.ERROR_CORRECT_H  # 30% recovery

    # Brand colors (from AppColors.terracotta)
    DEFAULT_FOREGROUND = '#C85A32'
    DEFAULT_BACKGROUND = '#FFFFFF'

    def generate_png(
        self,
        data: str,
        box_size: int = DEFAULT_BOX_SIZE,
        border: int = DEFAULT_BORDER,
        foreground: str = DEFAULT_FOREGROUND,
        background: str = DEFAULT_BACKGROUND,
    ) -> bytes:
        """
        Generate a QR code as PNG bytes.

        Args:
            data: The URL or text to encode.
            box_size: Size of each box in pixels.
            border: Border size in boxes.
            foreground: Foreground color (hex).
            background: Background color (hex).

        Returns:
            PNG image as bytes.
        """
        qr = qrcode.QRCode(
            version=None,  # Auto-size
            error_correction=self.DEFAULT_ERROR_CORRECTION,
            box_size=box_size,
            border=border,
        )
        qr.add_data(data)
        qr.make(fit=True)

        img = qr.make_image(
            fill_color=foreground,
            back_color=background,
        )

        buffer = io.BytesIO()
        img.save(buffer, format='PNG')
        return buffer.getvalue()

    def generate_svg(
        self,
        data: str,
        foreground: str = DEFAULT_FOREGROUND,
        background: str = DEFAULT_BACKGROUND,
    ) -> str:
        """
        Generate a QR code as SVG string.

        Args:
            data: The URL or text to encode.
            foreground: Foreground color (hex).
            background: Background color (hex).

        Returns:
            SVG string.
        """
        qr = segno.make(data, error='H')
        svg = qr.svg_inline(
            dark=foreground,
            light=background,
        )
        return svg

    def generate_data_uri(
        self,
        data: str,
        box_size: int = DEFAULT_BOX_SIZE,
        border: int = DEFAULT_BORDER,
        foreground: str = DEFAULT_FOREGROUND,
        background: str = DEFAULT_BACKGROUND,
    ) -> str:
        """
        Generate a QR code as a data URI (for embedding in HTML/JSON).

        Args:
            data: The URL or text to encode.
            box_size: Size of each box in pixels.
            border: Border size in boxes.
            foreground: Foreground color (hex).
            background: Background color (hex).

        Returns:
            Data URI string (data:image/png;base64,...).
        """
        import base64

        png_bytes = self.generate_png(
            data, box_size, border, foreground, background,
        )
        b64 = base64.b64encode(png_bytes).decode('utf-8')
        return f'data:image/png;base64,{b64}'

    def generate_for_artifact(self, artifact) -> dict:
        """
        Generate QR code for an artifact and return all formats.

        Args:
            artifact: An Artifact model instance.

        Returns:
            dict with 'svg', 'png_bytes', and 'data_uri' keys.
        """
        deep_link = artifact.qr_deep_link

        svg = self.generate_svg(deep_link)
        png_bytes = self.generate_png(deep_link)
        data_uri = self.generate_data_uri(deep_link)

        return {
            'svg': svg,
            'png_bytes': png_bytes,
            'data_uri': data_uri,
            'deep_link': deep_link,
        }


# Singleton instance
qr_generator = QRCodeGenerator()


def get_qr_generator() -> QRCodeGenerator:
    """Get the QR code generator instance."""
    return qr_generator


def generate_artifact_qr(
    artifact,
    *,
    fmt: str = PERSISTED_FORMAT,
    foreground: str = DEFAULT_FOREGROUND,
    background: str = DEFAULT_BACKGROUND,
    persist: bool = True,
):
    """Generate a QR code for `artifact` and, for SVG, store it on the row.

    Returns a dict with `format`, `deep_link`, and exactly one of `svg`,
    `png_bytes` or `data_uri` for the requested format.

    `persist=False` is what the dashboard's preview uses: a moderator
    recolouring a code should see the result without every colour they try
    having overwritten the one that is actually printed in the museum.
    """
    if fmt not in QR_FORMATS:
        raise ValueError(
            f'Unsupported QR format {fmt!r}; expected one of {QR_FORMATS}.'
        )

    generator = get_qr_generator()
    deep_link = artifact.qr_deep_link
    result = {'format': fmt, 'deep_link': deep_link}

    if fmt == 'svg':
        svg = generator.generate_svg(
            deep_link, foreground=foreground, background=background,
        )
        result['svg'] = svg
        if persist:
            artifact.qr_code_svg = svg
            artifact.save(update_fields=['qr_code_svg'])
    elif fmt == 'png':
        result['png_bytes'] = generator.generate_png(
            deep_link, foreground=foreground, background=background,
        )
    else:
        result['data_uri'] = generator.generate_data_uri(
            deep_link, foreground=foreground, background=background,
        )

    return result
