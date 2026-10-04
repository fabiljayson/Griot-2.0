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
    // Honour prefers-reduced-motion (`MediaQuery.disableAnimations`): present
    // the destination immediately instead of fading and drifting it in. The
    // route change itself is unaffected — only its decoration is dropped.
    if (MediaQuery.disableAnimationsOf(context)) return child;

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
///
/// The web app has had a dark theme all along (`darkMode: 'class'` over
/// `bg-mud-charcoal`); this brings the Flutter side to parity, reusing the four
/// tokens that were declared for it and never wired up.
abstract final class AppTheme {
  static ThemeData get light =>
      _build(_light, cardColor: _light.surface, scaffoldColor: AppColors.ivory);

  /// Accent colour for small text, resolved against the active theme.
  ///
  /// The bronze has no single tone that works as text on both grounds, so any
  /// accent-coloured *label* has to be resolved rather than hardcoded:
  /// `accentTextStrong` (5.74:1 on white) in light, `bronzeLight` (8.62:1 on
  /// charcoal) in dark. Hardcoding either one puts it at roughly 3:1 in the
  /// other theme — which is how `bronzeDark` ended up labelling story cards.
  static Color accentText(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? AppColors.bronzeLight
      : AppColors.accentTextStrong;

  /// Dark scheme.
  ///
  /// The one deliberate departure from the light scheme is `primary`. No step of
  /// the Ndop indigo ramp survives a charcoal ground — even `indigoLight`
  /// (#2A3B73) is only 1.76:1 — and `primary` is what paints outlined button
  /// labels, text buttons, the focus ring and the FAB. So the *accent* takes
  /// over as the interactive colour in dark, at `bronzeLight` (8.62:1 on the
  /// background). Indigo keeps the brand: it is the elevated card surface,
  /// which is where it reads best.
  static ThemeData get dark => _build(
    _dark,
    // Cards must lift off the background, and `surface` is the background.
    cardColor: _dark.surfaceContainer,
    // In dark the scaffold *is* `surface`. In light it deliberately is not: the
    // light scheme's `surface` is the white card colour and the ivory is the
    // page behind it. Deriving the scaffold from `surface` in both directions
    // silently turned the whole light app white.
    scaffoldColor: _dark.surface,
  );

  static const ColorScheme _light = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.indigo,
      onPrimary: Colors.white,
      primaryContainer: Color(0x1A1E2B58),
      onPrimaryContainer: AppColors.charcoal,
      secondary: AppColors.bronze,
      // Not white: white on the bronze secondary is 2.95:1. Keeping the bronze
      // fill and darkening only the label is the convention already used by
      // the one filled bronze button that had been fixed (story_detail_screen's
      // "Take Quiz"), so this makes the scheme agree with it.
      onSecondary: AppColors.charcoal,
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
      // `outline` is the functional boundary colour (inputs, focus rings,
      // toggles) and now clears WCAG 1.4.11's 3:1. Decorative card and
      // divider lines use `outlineVariant`, which stays quiet — a 3:1 hairline
      // around every card would turn the whole app into a wireframe.
      outline: AppColors.borderFunctional,
      outlineVariant: AppColors.dividerSoft,
      shadow: Color(0x141E2B58),
  );

  static const ColorScheme _dark = ColorScheme(
    brightness: Brightness.dark,
    // Bronze becomes the interactive colour; see `dark` above.
    primary: AppColors.bronzeLight,
    onPrimary: AppColors.mudCharcoal,
    primaryContainer: Color(0x33D9A84D),
    onPrimaryContainer: AppColors.textDark,
    secondary: AppColors.bronze,
    onSecondary: AppColors.mudCharcoal,
    secondaryContainer: Color(0x33C68B29),
    onSecondaryContainer: AppColors.textDark,
    tertiary: AppColors.equatorialGreenLight,
    onTertiary: AppColors.textDark,
    tertiaryContainer: Color(0x332D6A4F),
    onTertiaryContainer: AppColors.textDark,
    // `earthLight` rather than `earth`: #A0382B is 2.76:1 on charcoal and would
    // be unreadable as an error border or message. The lighter step puts white
    // on it at 4.69:1. The one thing it does not fully serve is error-coloured
    // *text* on the background, which measures 4.00:1 — see the note in
    // `ErrorState` before relying on that.
    error: AppColors.earthLight,
    onError: Colors.white,
    errorContainer: Color(0x33C44D3E),
    onErrorContainer: AppColors.textDark,
    surface: AppColors.mudCharcoal,
    onSurface: AppColors.textDark,
    onSurfaceVariant: AppColors.textDarkMuted,
    surfaceContainerLowest: AppColors.surfaceDarkLowest,
    surfaceContainerLow: AppColors.surfaceDarkLow,
    surfaceContainer: AppColors.surfaceDark,
    surfaceContainerHigh: AppColors.surfaceDarkHigh,
    surfaceContainerHighest: AppColors.surfaceDarkHighest,
    surfaceTint: AppColors.bronzeLight,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.dividerDark,
    shadow: Color(0x99000000),
  );

  /// Shared builder so the two schemes cannot drift apart.
  static ThemeData _build(
    ColorScheme scheme, {
    required Color cardColor,
    required Color scaffoldColor,
  }) {
    final base = ThemeData(
      brightness: scheme.brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldColor,
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
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            // Decorative, not a control boundary: the card's content and
            // elevation identify it, so this does not need 3:1.
            color: scheme.outlineVariant,
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
        color: scheme.outlineVariant,
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
        // Inverts with the theme: a charcoal bar on a charcoal screen would
        // read as nothing at all.
        backgroundColor: scheme.brightness == Brightness.dark
            ? AppColors.surfaceDarkHighest
            : AppColors.charcoal,
        contentTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          color: scheme.brightness == Brightness.dark
              ? AppColors.textDark
              : AppColors.ivory,
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