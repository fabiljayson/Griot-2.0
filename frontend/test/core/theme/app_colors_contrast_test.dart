import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/theme/app_colors.dart';
import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/admin/widgets/ranked_tile.dart';

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

  group('WCAG 1.4.11 non-text contrast — control boundaries', () {
    // 3:1 is required for the boundary of a control the user has to be able to
    // identify. `webBorder` is 1.24:1 on white, which is why every input in the
    // app previously read as borderless and an empty field looked disabled.
    test('borderFunctional clears 3:1 on white surfaces', () {
      expect(
        _contrast(AppColors.borderFunctional, AppColors.surfaceLight),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('borderFunctional clears 3:1 on ivory', () {
      expect(
        _contrast(AppColors.borderFunctional, AppColors.ivory),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('the theme wires the functional border to outline, not the soft one', () {
      // The regression that mattered: `scheme.outline` was `webBorder`.
      expect(AppTheme.light.colorScheme.outline, AppColors.borderFunctional);
    });

    test('card and divider borders use the quiet variant', () {
      expect(
        AppTheme.light.colorScheme.outlineVariant,
        AppColors.dividerSoft,
      );
    });

    test('the theme focus ring clears 3:1 on white surfaces', () {
      // `inputDecorationTheme.focusedBorder` uses `scheme.primary`; if the
      // primary ever darkens toward the accent this is the guard.
      expect(
        _contrast(
          AppTheme.light.colorScheme.primary,
          AppTheme.light.colorScheme.surface,
        ),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('bronzeDark clears 3:1 for the auth forms focus ring', () {
      expect(
        _contrast(AppColors.bronzeDark, AppColors.surfaceLight),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('WCAG AA contrast — text on a filled accent', () {
    // A filled bronze button is a fill, so the accent itself is the right
    // background. What has to change is the label: white on bronze is 2.95:1.
    // The convention across the app is to keep the fill and go charcoal.
    test('the theme does not put white text on the bronze secondary', () {
      expect(
        _contrast(
          AppTheme.light.colorScheme.onSecondary,
          AppTheme.light.colorScheme.secondary,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('charcoal on the bronze accent clears 4.5:1', () {
      expect(
        _contrast(AppColors.charcoal, AppColors.bronze),
        greaterThanOrEqualTo(4.5),
      );
    });

    test(
      'white on the bronze accent is below 4.5:1 (documented decorative pair)',
      () {
        expect(_contrast(const Color(0xFFFFFFFF), AppColors.bronze), lessThan(4.5));
      },
    );
  });

  group('RankedTile separates its decorative accent from its text accent', () {
    // The tile takes one `color` but uses it for both the chip fill and two
    // pieces of small bold text. Splitting them is what keeps the text legal.
    test('the default text accent clears 4.5:1 on ivory', () {
      expect(
        _contrast(const RankedTile(rank: 1, title: 'x').textColor, AppColors.ivory),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the text accent is not the decorative accent', () {
      final tile = const RankedTile(rank: 1, title: 'x');
      expect(tile.textColor, isNot(tile.color));
    });
  });
}
