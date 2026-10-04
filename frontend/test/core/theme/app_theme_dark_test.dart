import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_colors.dart';
import 'package:griot_ai/core/theme/app_theme.dart';

/// WCAG relative luminance and contrast.
///
/// Duplicated from `app_colors_contrast_test.dart` rather than shared: that
/// file asserts properties of individual palette tokens, this one asserts
/// properties of the assembled schemes. Coupling them would make a palette
/// change look like a theme failure.
double _luminance(Color color) {
  double channel(double s) =>
      s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// The Flutter app had no dark theme while the web app did (`darkMode: 'class'`
/// over `bg-mud-charcoal`), and four tokens — `mudCharcoal`, `surfaceDark`,
/// `textDark`, `textDarkMuted` — sat in the palette declared for a dark theme
/// that was never written.
///
/// The one design decision worth explaining is `primary`. No step of the Ndop
/// indigo ramp survives a charcoal ground — even `indigoLight` (#2A3B73) is
/// 1.76:1 — and `primary` is what paints outlined button labels, text buttons,
/// the input focus ring and the FAB. So in dark the *accent* becomes the
/// interactive colour and indigo keeps the brand as the elevated card surface,
/// where it reads best. That inverts the light hierarchy, so these tests exist
/// to hold the reasoning in place rather than to re-litigate it every time the
/// theme is touched.
void main() {
  final dark = AppTheme.dark.colorScheme;
  final light = AppTheme.light.colorScheme;

  group('dark scheme identity', () {
    test('is actually dark', () {
      expect(dark.brightness, Brightness.dark);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.mudCharcoal);
    });

    test('the light scaffold stays ivory, not the card white', () {
      // Regression guard: deriving `scaffoldBackgroundColor` from
      // `colorScheme.surface` turns the entire light app white, because the
      // light scheme's `surface` is the *card* colour and ivory is the page.
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.ivory);
      expect(AppTheme.light.scaffoldBackgroundColor, isNot(light.surface));
    });

    test('reuses the four tokens that were declared for it', () {
      expect(dark.surface, AppColors.mudCharcoal);
      expect(dark.surfaceContainer, AppColors.surfaceDark);
      expect(dark.onSurface, AppColors.textDark);
      expect(dark.onSurfaceVariant, AppColors.textDarkMuted);
    });

    test('light mode is unchanged by the refactor into a shared builder', () {
      expect(light.brightness, Brightness.light);
      expect(light.surface, AppColors.surfaceLight);
      expect(light.onSurface, AppColors.charcoal);
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.ivory);
    });

    test('cards lift off the background in dark, and do not in light', () {
      // In dark `surface` *is* the background, so a card painted `surface`
      // would be invisible. In light the card is the white and the background
      // is the ivory — the reverse relationship.
      expect(AppTheme.dark.cardTheme.color, dark.surfaceContainer);
      expect(
        _contrast(AppTheme.dark.cardTheme.color!, dark.surface),
        greaterThan(1.2),
      );
      expect(AppTheme.light.cardTheme.color, light.surface);
      expect(light.surface, isNot(light.onSurface));
    });

    test('the surface ramp ascends', () {
      // Material's ramp runs lowest -> lowest -> surface -> container -> ... ;
      // `surface` itself is a step, not the floor, which is why `ivory` and
      // `mudCharcoal` sit between the two `ContainerLow` steps here.
      final ramp = [
        dark.surfaceContainerLowest,
        dark.surface,
        dark.surfaceContainerLow,
        dark.surfaceContainer,
        dark.surfaceContainerHigh,
        dark.surfaceContainerHighest,
      ];
      final luminance = ramp.map(_luminance).toList();
      for (var i = 1; i < luminance.length; i++) {
        expect(
          luminance[i],
          greaterThan(luminance[i - 1]),
          reason: 'surfaceContainer step $i must be lighter than the one below',
        );
      }
    });
  });

  group('dark scheme contrast', () {
    test('onSurface and onSurfaceVariant clear 4.5:1 on the surface', () {
      expect(_contrast(dark.onSurface, dark.surface), greaterThanOrEqualTo(4.5));
      expect(
        _contrast(dark.onSurfaceVariant, dark.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('they also clear 4.5:1 on the elevated card surface', () {
      // Cards are the indigo `surfaceContainer`, not the charcoal background,
      // so every label inside one is measured against that.
      expect(
        _contrast(dark.onSurface, dark.surfaceContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.onSurfaceVariant, dark.surfaceContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('primary is legible on the surface — this is why it is bronze', () {
      expect(_contrast(dark.primary, dark.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(dark.onPrimary, dark.primary), greaterThanOrEqualTo(4.5));
    });

    test('no indigo tone would have worked as the dark primary', () {
      // The reason for the decision above, asserted so it stays a decision
      // rather than drifting back by accident.
      for (final indigo in [
        AppColors.indigo,
        AppColors.indigoDark,
        AppColors.indigoLight,
      ]) {
        expect(
          _contrast(indigo, dark.surface),
          lessThan(4.5),
          reason: '${indigo.toARGB32().toRadixString(16)} now passes as a dark '
              'primary — revisit the accent-primary decision',
        );
      }
    });

    test('secondary, tertiary and error pairs are legible as fills', () {
      expect(
        _contrast(dark.onSecondary, dark.secondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.onTertiary, dark.tertiary),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrast(dark.onError, dark.error), greaterThanOrEqualTo(4.5));
    });

    test('outline clears 3:1 on the surface', () {
      expect(
        _contrast(dark.outline, dark.surface),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('outlineVariant stays quiet', () {
      // The same reasoning as `dividerSoft`: a 3:1 hairline around every card
      // would turn the app into a wireframe.
      expect(_contrast(dark.outlineVariant, dark.surface), lessThan(3.0));
    });
  });

  group('accentText', () {
    test('resolves to the light-ground token in light mode', () {
      expect(AppTheme.accentText(light), AppColors.accentTextStrong);
    });

    test('resolves to the dark-ground token in dark mode', () {
      expect(AppTheme.accentText(dark), AppColors.bronzeLight);
    });

    test('whichever it returns, it clears 4.5:1 on that scheme surface', () {
      expect(
        _contrast(AppTheme.accentText(light), light.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppTheme.accentText(dark), dark.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the two tokens are genuinely different', () {
      // If these ever converge, the resolver is pointless and the hardcoded
      // values it replaced would have been fine.
      expect(AppTheme.accentText(light), isNot(AppTheme.accentText(dark)));
    });
  });

  group('snackbar', () {
    test('does not render a charcoal bar on a charcoal screen', () {
      final darkBar = AppTheme.dark.snackBarTheme.backgroundColor!;
      expect(darkBar, isNot(AppColors.charcoal));
      expect(
        _contrast(
          AppTheme.dark.snackBarTheme.contentTextStyle!.color!,
          darkBar,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('keeps its light appearance in light mode', () {
      expect(
        AppTheme.light.snackBarTheme.backgroundColor,
        AppColors.charcoal,
      );
    });
  });
}