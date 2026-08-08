import 'package:flutter/material.dart';

/// Griot 2.0 design system tokens.
///
/// The palette evokes sand, earth, and the African savannah —
/// Terracotta, Ochre, Savannah Green, and Deep Earth.
abstract final class AppColors {
  // --- Brand primaries -----------------------------------------------------
  /// Terracotta — primary brand color & interactive elements.
  static const Color terracotta = Color(0xFFC84C09);

  /// Dark terracotta for dark mode.
  static const Color terracottaDark = Color(0xFFE26D33);

  /// Savannah Green — accent & success.
  static const Color savannahGreen = Color(0xFF5B7040);

  /// Ochre — secondary accent & highlights.
  static const Color ochre = Color(0xFFD99B22);

  /// Dark ochre for dark mode.
  static const Color ochreDark = Color(0xFFE8B854);

  // --- Surfaces & ink ------------------------------------------------------
  /// Sand — light mode background.
  static const Color sand = Color(0xFFF9F5F0);

  /// Pure white — light mode surfaces.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Deep earth — light mode text.
  static const Color deepEarth = Color(0xFF2C241B);

  /// Secondary text in light mode.
  static const Color secondaryText = Color(0xFF6B5B4B);

  /// Mud charcoal — dark mode background.
  static const Color mudCharcoal = Color(0xFF1A1512);

  /// Dark mode surfaces.
  static const Color surfaceDark = Color(0xFF2C241B);

  /// Light text for dark mode.
  static const Color textDark = Color(0xFFF9F5F0);

  /// Border color.
  static const Color border = Color(0xFFE5D8C2);

  // --- Semantic ------------------------------------------------------------
  static const Color error = Color(0xFFD32F2F);

  // --- Compatibility aliases -----------------------------------------------
  static const Color parchment = sand;
  static const Color parchmentDark = Color(0xFFE9E0CC);
  static const Color charcoal = deepEarth;
  static const Color charcoalMuted = secondaryText;
  static const Color terracottaTint = Color(0xFFF3D9CC);
  static const Color ochreTint = Color(0xFFF6E7C8);
  static const Color savannahGreenTint = Color(0xFFDCE8D5);
}
