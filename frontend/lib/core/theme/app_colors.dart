import 'package:flutter/material.dart';

/// Ancient Manuscript design tokens.
///
/// The palette evokes aged parchment, earthen clays, and the African
/// savannah — Terracotta, Ochre, Savannah Green, Parchment, and Charcoal.
abstract final class AppColors {
  // --- Brand primaries -----------------------------------------------------
  /// Burnt clay red — primary brand color & interactive elements.
  static const Color terracotta = Color(0xFFC85A32);

  /// Deepened terracotta for pressed / hover states.
  static const Color terracottaDark = Color(0xFF9E3F1F);

  /// Soft terracotta tint used for chips, fills, and surfaces.
  static const Color terracottaTint = Color(0xFFF3D9CC);

  /// Golden savannah ochre — secondary accent & highlights.
  static const Color ochre = Color(0xFFD99B26);

  /// Pale ochre tint for subtle backgrounds.
  static const Color ochreTint = Color(0xFFF6E7C8);

  /// Rich savannah green — success, badges, natural motifs.
  static const Color savannahGreen = Color(0xFF2D5A27);

  /// Soft green tint for success surfaces.
  static const Color savannahGreenTint = Color(0xFFDCE8D5);

  // --- Surfaces & ink ------------------------------------------------------
  /// Aged parchment — the app's primary light surface.
  static const Color parchment = Color(0xFFF4EFE6);

  /// Slightly deeper parchment for layered surfaces / cards.
  static const Color parchmentDark = Color(0xFFE9E0CC);

  /// Charcoal ink — primary text color on light surfaces.
  static const Color charcoal = Color(0xFF222222);

  /// Lighter charcoal for secondary text.
  static const Color charcoalMuted = Color(0xFF5C564C);

  // --- Semantic ------------------------------------------------------------
  static const Color error = Color(0xFFB3261E);
  static const Color gold = Color(0xFFC9A227);
}
