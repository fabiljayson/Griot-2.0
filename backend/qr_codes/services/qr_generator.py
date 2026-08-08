"""
QR code generation service for museum artifacts.

Generates QR codes that link to artifact detail pages.
Supports PNG and SVG output formats.
"""
import io
import qrcode
import segno


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
