import 'package:flutter/material.dart';

/// Typography for the African Teller design system.
///
/// Body text uses the platform sans-serif for readability; display and
/// heading text falls back to serif families (Georgia / Noto Serif) to evoke
/// the engraved, manuscript feel of the brand.
abstract final class AppTypography {
  /// Font fallback chain applied to display / heading styles.
  static const List<String> _serifFallback = ['Georgia', 'Noto Serif', 'serif'];

  static TextStyle _display(double size, FontWeight weight, Color color) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.15,
        letterSpacing: 0.2,
        fontFamilyFallback: _serifFallback,
      );

  /// Build the full [TextTheme] used by [ThemeData].
  static TextTheme textTheme({required ColorScheme colorScheme}) {
    final ink = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    return TextTheme(
      // Display / hero styles — manuscript serif.
      displayLarge: _display(57, FontWeight.w600, ink),
      displayMedium: _display(45, FontWeight.w600, ink),
      displaySmall: _display(36, FontWeight.w600, ink),
      headlineLarge: _display(32, FontWeight.w600, ink),
      headlineMedium: _display(28, FontWeight.w600, ink),
      headlineSmall: _display(24, FontWeight.w600, ink),
      titleLarge: _display(22, FontWeight.w600, ink),
      titleMedium: _display(16, FontWeight.w600, ink),
      titleSmall: _display(14, FontWeight.w600, ink),
      // Body text — clean sans-serif.
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: muted,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: 0.3,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.4,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.6,
      ),
    );
  }

  /// Accent style for quote / wisdom text in the story reader (Phase 3).
  static TextStyle quoteStyle({required Color color, double size = 20}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.6,
        fontStyle: FontStyle.italic,
        fontFamilyFallback: _serifFallback,
      );
}
