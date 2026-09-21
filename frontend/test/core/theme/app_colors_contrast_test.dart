import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/theme/app_colors.dart';

/// WCAG 2.x relative luminance (0.0 – 1.0).
///
/// `Color.r/g/b` are normalized 0.0–1.0 doubles in current Flutter.
double _luminance(Color color) {
  double channel(double s) =>
      s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG contrast ratio between two colors (1.0 – 21.0).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('WCAG AA contrast — accent text on ivory', () {
    // Small (<18pt) text must pass 4.5:1 on the light background.
    test('accentTextStrong clears 4.5:1 on ivory', () {
      expect(
        _contrast(AppColors.accentTextStrong, AppColors.ivory),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('accentTextStrong clears 4.5:1 on white surfaces', () {
      expect(
        _contrast(AppColors.accentTextStrong, AppColors.surfaceLight),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('accentTextStrongIndigo clears 4.5:1 on ivory', () {
      expect(
        _contrast(AppColors.accentTextStrongIndigo, AppColors.ivory),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('accentTextStrongGreen clears 4.5:1 on ivory', () {
      expect(
        _contrast(AppColors.accentTextStrongGreen, AppColors.ivory),
        greaterThanOrEqualTo(4.5),
      );
    });

    // Body/metadata ink on the light background.
    test('ink (charcoal) clears 4.5:1 on ivory', () {
      expect(
        _contrast(AppColors.charcoal, AppColors.ivory),
        greaterThanOrEqualTo(4.5),
      );
    });

    // Dark mode: light text on the dark surface.
    test('textDark clears 4.5:1 on surfaceDark', () {
      expect(
        _contrast(AppColors.textDark, AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('textDarkMuted clears 4.5:1 on surfaceDark', () {
      expect(
        _contrast(AppColors.textDarkMuted, AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5),
      );
    });

    // The raw bronze is decorative; it must NOT be the one masquerading as
    // small text. Guard against a regression to the bright accent.
    test(
      'raw bronze on ivory is below 4.5:1 (documented decorative token)',
      () {
        expect(_contrast(AppColors.bronze, AppColors.ivory), lessThan(4.5));
      },
    );
  });
}
