/// Spacing, radius and elevation tokens for the Griot 2.0 design system.
///
/// Single source of truth so screens stop inventing their own padding and
/// radii. Values mirror the Tailwind scale used by the webapp
/// (`backend/static/web/js/tailwind-theme.js` + the templates' utility
/// classes), so the Flutter layout rhythm matches the browser.
abstract final class AppSpacing {
  /// 4-pt base unit.
  static const double unit = 4;

  /// Extra-small — icon/text gaps. (web: `gap-1` / `space-y-1`)
  static const double xs = 4;

  /// Small — inside compact rows. (web: `gap-2` / `p-2`)
  static const double sm = 8;

  /// Medium — default vertical rhythm between related elements.
  static const double md = 12;

  /// Large — card padding, screen gutters on compact widths.
  /// (web: `p-4` / `px-4`)
  static const double lg = 16;

  /// Extra-large — gaps between cards in a list. (web: `mb-5`)
  static const double xl = 20;

  /// Section separation. (web: `mb-8` / `mb-12`)
  static const double section = 32;

  /// Large section separation before a trailing element. (web: `mb-10`)
  static const double sectionLarge = 48;

  /// Screen gutter on wide layouts (>= 600 logical px).
  static const double gutterWide = 24;

  /// Maximum readable content width for text-heavy panels.
  static const double maxContentWidth = 960;
}

/// Corner radius tokens.
abstract final class AppRadius {
  /// Chips and small badges. (web: `rounded-lg`)
  static const double chip = 10;

  /// Inputs, buttons. (web: `rounded-xl`)
  static const double control = 12;

  /// Cards and panels. (web: `rounded-2xl`)
  static const double card = 16;

  /// Hero panels and pills. (web: `rounded-3xl`)
  static const double hero = 24;

  /// Fully rounded (pills, avatars, rings).
  static const double pill = 999;
}

/// Reusable component sizes so buttons/avatars stay consistent.
abstract final class AppSizes {
  /// Minimum tap target for primary/secondary buttons.
  static const double buttonHeight = 48;

  /// Comfortable button height used on auth screens.
  static const double buttonHeightLarge = 52;

  /// Bottom navigation bar height.
  static const double navBarHeight = 64;

  /// Diameter of the elevated centre action in the bottom bar.
  static const double navActionSize = 56;

  /// Standard list thumbnail.
  static const double thumb = 60;

  /// Story card cover aspect ratio (web story_card.html: `aspect-[16/9]`).
  static const double coverAspect = 16 / 9;
}
