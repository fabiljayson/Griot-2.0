import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Subtle African-inspired diamond/kente pattern painter.
///
/// Used as a decorative overlay on authentication branding panels.
/// Shared between login, register, and loading screens.
class BrandPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.terracotta.withValues(alpha: 0.04)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const spacing = 60.0;
    final rows = (size.height / spacing).ceil();
    final cols = (size.width / spacing).ceil();

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = c * spacing + spacing / 2;
        final cy = r * spacing + spacing / 2;
        final half = spacing * 0.3;

        // Diamond
        final path = Path()
          ..moveTo(cx, cy - half)
          ..lineTo(cx + half, cy)
          ..lineTo(cx, cy + half)
          ..lineTo(cx - half, cy)
          ..close();
        canvas.drawPath(path, paint);

        // Inner cross
        canvas.drawLine(
          Offset(cx - half * 0.4, cy),
          Offset(cx + half * 0.4, cy),
          paint..color = AppColors.ochre.withValues(alpha: 0.03),
        );
        canvas.drawLine(
          Offset(cx, cy - half * 0.4),
          Offset(cx, cy + half * 0.4),
          paint..color = AppColors.ochre.withValues(alpha: 0.03),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
