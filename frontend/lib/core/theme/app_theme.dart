import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Built-in page transition used by every `MaterialPageRoute` in the app: a
/// soft fade with a slight upward drift, so pushed screens feel connected to
/// the Griot identity instead of the default platform slide.
class GriotPageTransitionsBuilder extends PageTransitionsBuilder {
  const GriotPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Builds the full ThemeData for the Griot 2.0 app, mirroring the webapp's
/// Tailwind theme (Ndop indigo primary, bronze accent, ivory surfaces).
abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.indigo,
      onPrimary: Colors.white,
      primaryContainer: Color(0x1A1E2B58),
      onPrimaryContainer: AppColors.charcoal,
      secondary: AppColors.bronze,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.bronzeTint,
      onSecondaryContainer: AppColors.charcoal,
      tertiary: AppColors.equatorialGreen,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.equatorialGreenTint,
      onTertiaryContainer: AppColors.charcoal,
      error: AppColors.earth,
      onError: Colors.white,
      errorContainer: AppColors.earthTint,
      onErrorContainer: AppColors.charcoal,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.charcoal,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerHighest: AppColors.ivory,
      surfaceContainerHigh: AppColors.ivory,
      surfaceContainer: AppColors.ivory,
      surfaceTint: AppColors.indigo,
      outline: AppColors.webBorder,
      shadow: Color(0x14000000),
    );

    final base = ThemeData(
      brightness: Brightness.light,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.ivory,
      textTheme: AppTypography.textTheme(colorScheme: scheme),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GriotPageTransitionsBuilder(),
          TargetPlatform.iOS: GriotPageTransitionsBuilder(),
          TargetPlatform.linux: GriotPageTransitionsBuilder(),
          TargetPlatform.macOS: GriotPageTransitionsBuilder(),
          TargetPlatform.windows: GriotPageTransitionsBuilder(),
          TargetPlatform.fuchsia: GriotPageTransitionsBuilder(),
        },
      ),
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
        backgroundColor: AppColors.charcoal,
        contentTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: AppColors.ivory,
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