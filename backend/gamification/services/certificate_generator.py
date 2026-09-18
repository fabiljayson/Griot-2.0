"""
PDF certificate generator for heritage achievement certificates.

Generates branded PDF certificates that users can download and share.
Uses reportlab for PDF creation with the Cameroonian heritage color palette.
"""

import io
import logging
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas

logger = logging.getLogger(__name__)

# Brand colors (from README.md)
CAMINDIGO = colors.HexColor('#1E2B58')
CAMBRONZE = colors.HexColor('#C68B29')
CAMEARTH = colors.HexColor('#A0382B')
CAMGREEN = colors.HexColor('#1B4332')
CAMIVORY = colors.HexColor('#FBF9F4')

CERTIFICATE_WIDTH = 11 * inch
CERTIFICATE_HEIGHT = 8.5 * inch


def generate_certificate_pdf(
    title: str,
    username: str,
    description: str,
    certificate_number: str,
    certificate_type: str,
    issued_at: datetime,
    stories_read: int = 0,
    quizzes_passed: int = 0,
    level_achieved: int = 1,
) -> bytes:
    """Generate a branded heritage certificate as PDF bytes.

    Args:
        title: Certificate title (e.g., "Reading Achievement").
        username: Recipient's username.
        description: Certificate description.
        certificate_number: Unique certificate ID.
        certificate_type: Type of certificate.
        issued_at: Date/time of issue.
        stories_read: Number of stories read.
        quizzes_passed: Number of quizzes passed.
        level_achieved: Gamification level achieved.

    Returns:
        PDF file as bytes.
    """
    buffer = io.BytesIO()
    c = canvas.Canvas(buffer, pagesize=(CERTIFICATE_WIDTH, CERTIFICATE_HEIGHT))

    # --- Background ---
    c.setFillColor(CAMIVORY)
    c.rect(0, 0, CERTIFICATE_WIDTH, CERTIFICATE_HEIGHT, fill=True, stroke=False)

    # --- Border ---
    margin = 0.4 * inch
    c.setStrokeColor(CAMBRONZE)
    c.setLineWidth(3)
    c.roundRect(margin, margin, CERTIFICATE_WIDTH - 2 * margin, CERTIFICATE_HEIGHT - 2 * margin, 15)

    # Inner border
    inner_margin = 0.55 * inch
    c.setStrokeColor(CAMINDIGO)
    c.setLineWidth(1)
    c.roundRect(inner_margin, inner_margin, CERTIFICATE_WIDTH - 2 * inner_margin, CERTIFICATE_HEIGHT - 2 * inner_margin, 12)

    # --- Header ---
    y = CERTIFICATE_HEIGHT - 1.2 * inch

    # Platform name
    c.setFillColor(CAMINDIGO)
    c.setFont('Helvetica-Bold', 14)
    c.drawCentredString(CERTIFICATE_WIDTH / 2, y, 'AFRICAN TELLER')
    y -= 0.3 * inch

    # Divider line
    c.setStrokeColor(CAMBRONZE)
    c.setLineWidth(2)
    line_width = 3 * inch
    c.line(
        (CERTIFICATE_WIDTH - line_width) / 2, y,
        (CERTIFICATE_WIDTH + line_width) / 2, y,
    )
    y -= 0.45 * inch

    # Certificate title
    c.setFillColor(CAMEARTH)
    c.setFont('Helvetica-Bold', 28)
    c.drawCentredString(CERTIFICATE_WIDTH / 2, y, 'Certificate of Achievement')
    y -= 0.4 * inch

    # Achievement type
    c.setFillColor(CAMINDIGO)
    c.setFont('Helvetica', 16)
    c.drawCentredString(CERTIFICATE_WIDTH / 2, y, title)
    y -= 0.5 * inch

    # --- Recipient ---
    c.setFillColor(colors.HexColor('#666666'))
    c.setFont('Helvetica', 12)
    c.drawCentredString(CERTIFICATE_WIDTH / 2, y, 'This certificate is proudly presented to')
    y -= 0.4 * inch

    c.setFillColor(CAMINDIGO)
    c.setFont('Helvetica-Bold', 24)
    c.drawCentredString(CERTIFICATE_WIDTH / 2, y, username)
    y -= 0.35 * inch

    # Underline for name
    name_width = c.stringWidth(username, 'Helvetica-Bold', 24)
    c.setStrokeColor(CAMBRONZE)
    c.setLineWidth(1.5)
    c.line(
        (CERTIFICATE_WIDTH - name_width) / 2 - 10, y,
        (CERTIFICATE_WIDTH + name_width) / 2 + 10, y,
    )
    y -= 0.45 * inch

    # --- Description ---
    c.setFillColor(colors.HexColor('#444444'))
    c.setFont('Helvetica', 11)
    # Word-wrap description
    words = description.split()
    lines = []
    current_line = ''
    for word in words:
        test = f'{current_line} {word}'.strip()
        if c.stringWidth(test, 'Helvetica', 11) < CERTIFICATE_WIDTH - 2 * inch:
            current_line = test
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
    if current_line:
        lines.append(current_line)

    for line in lines[:3]:  # Max 3 lines
        c.drawCentredString(CERTIFICATE_WIDTH / 2, y, line)
        y -= 0.2 * inch

    y -= 0.2 * inch

    # --- Stats ---
    c.setFillColor(CAMINDIGO)
    c.setFont('Helvetica', 10)
    stats_parts = []
    if stories_read > 0:
        stats_parts.append(f'{stories_read} stories read')
    if quizzes_passed > 0:
        stats_parts.append(f'{quizzes_passed} quizzes passed')
    if level_achieved > 1:
        stats_parts.append(f'Level {level_achieved}')
    if stats_parts:
        c.drawCentredString(CERTIFICATE_WIDTH / 2, y, ' · '.join(stats_parts))
        y -= 0.3 * inch

    # --- Footer ---
    y = 1.3 * inch

    # Divider
    c.setStrokeColor(CAMBRONZE)
    c.setLineWidth(1)
    c.line(
        (CERTIFICATE_WIDTH - line_width) / 2, y,
        (CERTIFICATE_WIDTH + line_width) / 2, y,
    )
    y -= 0.25 * inch

    # Certificate number and date
    c.setFillColor(colors.HexColor('#888888'))
    c.setFont('Helvetica', 9)
    c.drawCentredString(
        CERTIFICATE_WIDTH / 2, y,
        f'{certificate_number}  ·  Issued {issued_at.strftime("%B %d, %Y")}',
    )
    y -= 0.2 * inch
    c.drawCentredString(
        CERTIFICATE_WIDTH / 2, y,
        'africanteller.org',
    )

    c.save()
    return buffer.getvalue()
