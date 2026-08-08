import 'package:flutter/material.dart';

/// Typography for the Griot 2.0 design system.
///
/// Hero/Headlines: Fraunces (warm, storytelling serif).
/// Body/UI: Plus Jakarta Sans.
abstract final class AppTypography {
  /// Build the full [TextTheme] used by [ThemeData].
  static TextTheme textTheme({required ColorScheme colorScheme}) {
    final ink = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;

    return TextTheme(
      // Display / hero styles — Fraunces serif.
      displayLarge: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ink,
        height: 1.15,
        letterSpacing: 0.2,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.25,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.35,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Fraunces',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
        height: 1.4,
      ),
      // Body text — Plus Jakarta Sans.
      bodyLarge: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: ink,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: 0.3,
      ),
      labelMedium: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
        letterSpacing: 0.4,
      ),
      labelSmall: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: muted,
        letterSpacing: 0.6,
      ),
    );
  }

  /// Accent style for quote / wisdom text in the story reader.
  static TextStyle quoteStyle({required Color color, double size = 20}) =>
      TextStyle(
        fontFamily: 'Fraunces',
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.6,
        fontStyle: FontStyle.italic,
      );
}
