import 'package:flutter/material.dart';

/// Griot 2.0 design system tokens.
///
/// Cameroonian heritage palette mirroring the Griot AI webapp
/// (templates/web/base.html Tailwind config):
///   - Royal Ndop indigo  #1E2B58 — primary
///   - Foumban bronze     #C68B29 — accent
///   - Highland earth     #A0382B — error/danger accent
///   - Equatorial green   #1B4332 — success
///   - Raffia ivory       #FBF9F4 — background neutral
///   - Slate charcoal     #1C1C1E — dark text
///   - Mud charcoal       #0F1219 — dark mode background
///
/// Legacy alias names (terracotta, ochre, savannahGreen, sand, deepEarth…)
/// are kept so existing call sites keep working; they now resolve to the
/// web palette equivalents.
abstract final class AppColors {
  // --- Brand primaries -----------------------------------------------------
  /// Royal Ndop indigo — primary brand color & interactive elements
  /// (web: `cam-indigo`).
  static const Color indigo = Color(0xFF1E2B58);

  /// Darker Ndop indigo for dark mode / gradients (web: `cam-indigo-dark`).
  static const Color indigoDark = Color(0xFF151F42);

  /// Lighter indigo (web: `cam-indigo-light`).
  static const Color indigoLight = Color(0xFF2A3B73);

  /// Foumban bronze — accent & highlights (web: `cam-bronze`).
  static const Color bronze = Color(0xFFC68B29);

  /// Dark bronze (web: `cam-bronze-dark`).
  static const Color bronzeDark = Color(0xFFA67420);

  /// Light bronze (web: `cam-bronze-light`).
  static const Color bronzeLight = Color(0xFFD9A84D);

  /// Bronze tint — subtle highlight surfaces (web: `cam-bronze-tint`).
  static const Color bronzeTint = Color(0xFFF5ECD6);

  /// Highland earth — danger/destructive accents (web: `cam-earth`).
  static const Color earth = Color(0xFFA0382B);

  /// Dark earth (web: `cam-earth-dark`).
  static const Color earthDark = Color(0xFF852D22);

  /// Light earth (web: `cam-earth-light`).
  static const Color earthLight = Color(0xFFC44D3E);

  /// Earth tint (web: `cam-earth-tint`).
  static const Color earthTint = Color(0xFFF4DDD9);

  /// Equatorial green — success (web: `cam-green`).
  static const Color equatorialGreen = Color(0xFF1B4332);

  /// Dark green (web: `cam-green-dark`).
  static const Color equatorialGreenDark = Color(0xFF143326);

  /// Light green (web: `cam-green-light`).
  static const Color equatorialGreenLight = Color(0xFF2D6A4F);

  /// Green tint (web: `cam-green-tint`).
  static const Color equatorialGreenTint = Color(0xFFD8E8E0);

  // --- Surfaces & ink ------------------------------------------------------
  /// Raffia ivory — light mode background (web: `cam-ivory`).
  static const Color ivory = Color(0xFFFBF9F4);

  /// Pure white — light mode card surfaces (web: `cam-white`).
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Slate charcoal — light mode text (web: `cam-dark`).
  static const Color charcoal = Color(0xFF1C1C1E);

  /// Secondary text (web: `cam-muted`).
  static const Color muted = Color(0xFF6B7280);

  /// Web border neutral (web: `brand-border`).
  static const Color webBorder = Color(0xFFE5E7EB);

  /// Mud charcoal — dark mode background (web: `mud-charcoal`).
  static const Color mudCharcoal = Color(0xFF0F1219);

  /// Dark mode surfaces — Ndop indigo (web: `warm-brown` alias).
  static const Color surfaceDark = Color(0xFF1E2B58);

  /// Light text for dark mode — Raffia ivory (web: dark `text-sand`).
  static const Color textDark = Color(0xFFFBF9F4);

  /// Dark mode secondary text (web: dark `.story-content` gray).
  static const Color textDarkMuted = Color(0xFFD1D5DB);

  /// Border color.
  static const Color border = webBorder;

  // --- Semantic ------------------------------------------------------------
  /// Error — Highland earth red (web: `cam-earth` / `cam-error` fallback).
  static const Color error = Color(0xFFA0382B);

  /// Success — Equatorial green (web: `bg-savannah` toasts).
  static const Color success = Color(0xFF1B4332);

  // --- Compatibility aliases -----------------------------------------------
  // NOTE: these aliases intentionally resolve to the *same* values as the
  // legacy aliases in `backend/static/web/js/tailwind-theme.js`, so a call
  // site keeps the same colour on both platforms:
  //   terracotta → cam-bronze, ochre → cam-bronze, savannah → cam-green,
  //   sand → cam-ivory, deep-earth → cam-dark, secondary-text → cam-muted.

  /// Legacy name → Foumban bronze (web `terracotta.DEFAULT`).
  static const Color terracotta = bronze;

  /// Legacy name → dark bronze (web `terracotta.dark`).
  static const Color terracottaDark = bronzeDark;

  /// Legacy name → now Equatorial green (web `savannah`).
  static const Color savannahGreen = equatorialGreen;

  /// Legacy name → now Foumban bronze (the web's actual accent).
  static const Color ochre = bronze;

  /// Legacy name → dark bronze (web `ochre.dark` = `cam-bronze-dark`).
  static const Color ochreDark = bronzeDark;

  /// Legacy name → now Raffia ivory (web `sand`).
  static const Color sand = ivory;

  /// Legacy name → now slate charcoal (web `deep-earth`).
  static const Color deepEarth = charcoal;

  /// Legacy name → now web muted gray (web `secondary-text`).
  static const Color secondaryText = muted;

  /// Legacy name → now surface dark indigo.
  static const Color surfaceDarkAlias = surfaceDark;

  /// Legacy tint — bronze wash (web `terracotta.tint` = `cam-bronze-tint`).
  static const Color terracottaTint = bronzeTint;

  /// Legacy tint — bronze wash (web `cam-bronze-tint`).
  static const Color ochreTint = bronzeTint;

  /// Legacy tint — green wash (web `cam-green-tint`).
  static const Color savannahGreenTint = equatorialGreenTint;

  /// Legacy name → now Raffia ivory (quote cards & parchment surfaces).
  static const Color parchment = ivory;

  /// Legacy name → now web border neutral.
  static const Color parchmentDark = webBorder;

  /// Legacy name → now web muted gray.
  static const Color charcoalMuted = muted;

  // --- Semantic accent tokens (WCAG AA) -------------------------------------
  /// Strong bronze for small accent text on ivory/white. Darkened from
  /// `bronze` (#C68B29, ~2.8:1) to ~#8A5D13 so it clears 4.5:1 on ivory.
  /// Use for region badges, summary boxes, role badges, small bronze labels.
  static const Color accentTextStrong = Color(0xFF8A5D13);

  /// Strong indigo for small accent text on ivory/white. Clears 4.5:1 on
  /// ivory; use for section titles and small primary accent labels.
  static const Color accentTextStrongIndigo = Color(0xFF151F42);

  /// Strong green for small accent text on ivory/white.
  static const Color accentTextStrongGreen = Color(0xFF0E3326);
}
