import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the full ThemeData for the Griot 2.0 app.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.terracottaDark : AppColors.terracotta,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? AppColors.terracottaDark.withValues(alpha: 0.2)
          : AppColors.terracotta.withValues(alpha: 0.1),
      onPrimaryContainer: isDark ? AppColors.textDark : AppColors.deepEarth,
      secondary: isDark ? AppColors.ochreDark : AppColors.ochre,
      onSecondary: isDark ? AppColors.deepEarth : Colors.white,
      secondaryContainer: isDark
          ? AppColors.ochreDark.withValues(alpha: 0.2)
          : AppColors.ochre.withValues(alpha: 0.1),
      onSecondaryContainer: isDark ? AppColors.textDark : AppColors.deepEarth,
      tertiary: AppColors.savannahGreen,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.savannahGreen.withValues(alpha: 0.1),
      onTertiaryContainer: isDark ? AppColors.textDark : AppColors.deepEarth,
      error: AppColors.error,
      onError: Colors.white,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.textDark : AppColors.deepEarth,
      onSurfaceVariant: isDark
          ? AppColors.textDark.withValues(alpha: 0.7)
          : AppColors.secondaryText,
      surfaceContainerHighest: isDark
          ? AppColors.surfaceDark.withValues(alpha: 0.8)
          : AppColors.sand,
      outline: isDark
          ? AppColors.textDark.withValues(alpha: 0.2)
          : AppColors.border,
      shadow: Colors.black.withValues(alpha: 0.08),
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? AppColors.mudCharcoal : AppColors.sand,
      textTheme: AppTypography.textTheme(colorScheme: scheme),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme(colorScheme: scheme)
            .headlineSmall
            ?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outline,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondaryContainer,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: scheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.deepEarth,
        contentTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: isDark ? AppColors.textDark : AppColors.sand,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
