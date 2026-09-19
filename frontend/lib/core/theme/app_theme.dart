import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the full ThemeData for the Griot 2.0 app, mirroring the webapp's
/// Tailwind theme (Ndop indigo primary, bronze accent, ivory surfaces).
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.indigoLight : AppColors.indigo,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? AppColors.indigoLight.withValues(alpha: 0.25)
          : AppColors.indigo.withValues(alpha: 0.1),
      onPrimaryContainer: isDark ? AppColors.textDark : AppColors.charcoal,
      secondary: isDark ? AppColors.bronzeLight : AppColors.bronze,
      onSecondary: isDark ? AppColors.charcoal : Colors.white,
      secondaryContainer: isDark
          ? AppColors.bronzeLight.withValues(alpha: 0.2)
          : AppColors.bronzeTint,
      onSecondaryContainer: isDark ? AppColors.textDark : AppColors.charcoal,
      tertiary: isDark ? AppColors.equatorialGreenLight : AppColors.equatorialGreen,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.equatorialGreenTint,
      onTertiaryContainer: isDark ? AppColors.textDark : AppColors.charcoal,
      error: isDark ? AppColors.earthLight : AppColors.earth,
      onError: Colors.white,
      surface: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.textDark : AppColors.charcoal,
      onSurfaceVariant: isDark
          ? AppColors.textDarkMuted
          : AppColors.muted,
      surfaceContainerHighest: isDark
          ? AppColors.indigoDark
          : AppColors.ivory,
      surfaceContainerHigh: isDark
          ? AppColors.indigoDark
          : AppColors.ivory,
      surfaceContainer: isDark
          ? AppColors.indigoDark
          : AppColors.ivory,
      surfaceTint: isDark ? AppColors.indigoLight : AppColors.indigo,
      outline: isDark
          ? Color(0xFF3A4A7A) // indigo-tinted border for dark surfaces
          : AppColors.webBorder,
      shadow: Colors.black.withValues(alpha: 0.08),
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? AppColors.mudCharcoal : AppColors.ivory,
      textTheme: AppTypography.textTheme(colorScheme: scheme),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.indigoDark : scheme.surface,
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
        fillColor: isDark ? AppColors.indigoDark : scheme.surface,
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
        backgroundColor: isDark ? AppColors.indigoDark : scheme.surface,
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
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.charcoal,
        contentTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: isDark ? AppColors.textDark : AppColors.ivory,
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
