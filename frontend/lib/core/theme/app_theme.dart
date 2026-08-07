import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the full ThemeData for the African Teller app.
///
/// Light theme: parchment surfaces with charcoal ink.
/// Dark theme: charcoal surfaces with parchment ink ("night reader").
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.terracotta : AppColors.terracotta,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? AppColors.terracottaDark
          : AppColors.terracottaTint,
      onPrimaryContainer: isDark ? AppColors.parchment : AppColors.terracottaDark,
      secondary: AppColors.ochre,
      onSecondary: isDark ? AppColors.charcoal : Colors.white,
      secondaryContainer: AppColors.ochreTint,
      onSecondaryContainer: AppColors.charcoal,
      tertiary: AppColors.savannahGreen,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.savannahGreenTint,
      onTertiaryContainer: AppColors.charcoal,
      error: AppColors.error,
      onError: Colors.white,
      surface: isDark ? AppColors.charcoal : AppColors.parchment,
      onSurface: isDark ? AppColors.parchment : AppColors.charcoal,
      surfaceContainerHighest: isDark
          ? AppColors.charcoalMuted
          : AppColors.parchmentDark,
      onSurfaceVariant:
          isDark ? AppColors.ochreTint : AppColors.charcoalMuted,
      outline: isDark ? AppColors.ochreTint : AppColors.charcoalMuted,
      shadow: Colors.black,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: AppTypography.textTheme(colorScheme: scheme),
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme(colorScheme: scheme)
            .titleLarge
            ?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF2C2C2C) : AppColors.parchmentDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outline.withValues(alpha: 0.15),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF2C2C2C)
            : Colors.white.withValues(alpha: 0.7),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.15),
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.terracottaDark : AppColors.charcoal,
        contentTextStyle: const TextStyle(color: AppColors.parchment),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }
}
