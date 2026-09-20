# Feature Specification: UI Design & Frontend Remediation

**Feature Branch**: `002-ui-frontend-remediation`

**Created**: 2026-09-20

**Status**: Approved — ready for implementation

**Input**: UI design & frontend audit of `griot_ai` against `.agents/skills/`
(frontend-design, accessibility, inclusive-design, flutter-best-practices,
flutter-use-column-row-first, code-review). Complements
`001-flutter-skill-remediation` (which covers state/errors/tests/hygiene);
this spec covers the design-system, theming, accessibility, i18n, and
UI-functional dimension that spec does not track.

---

## Audit Verdict

**Design foundation: GOOD.** Distinctive Fraunces + Plus Jakarta Sans
typography, a documented Cameroonian heritage palette with web parity, full
hand-built light/dark `ColorScheme`, M3, responsive habits
(`MediaQuery.sizeOf`, breakpoints, slivers, `SafeArea`), and modern API usage
(`withValues`, exhaustive `switch` on sealed states). `flutter analyze` = 0
issues.

**Execution consistency: CHANGES REQUESTED.** ~54 `Colors.white` usages across
20 files bypass the dark scheme (library screen and badge card render light in
dark mode), bronze accent text fails WCAG AA (~2.8:1 on ivory), **zero**
`Semantics` in the app with 16 unlabelled `GestureDetector` controls, tap
targets as small as ~20px, i18n is cosmetic (no `.arb` files; a local
`_isEnglish` bool), ~90 hardcoded `fontSize:` literals bypass the type scale,
discontinued `flutter_markdown` dependency, dead Share/Quiz/Region buttons,
and a search clear button that never appears.

---

## User Scenarios & Testing

### User Story 1 — Dark mode renders correctly on every screen (Priority: P1)

The theme defines a dark `ColorScheme`, but many widgets bypass it with
hardcoded light colors:

- `library_screen.dart:47-50` — `Scaffold`/`AppBar` hardcoded to
  `AppColors.parchment` (light ivory) with `charcoal` text; continue-card
  uses `Colors.white` (line ~141). Whole screen renders light in dark mode.
- `badge_card.dart:75` — `_buildFull` uses `Colors.white` /
  `Colors.white.withValues(alpha: 0.5)` card backgrounds.
- `home_screen.dart` `_StoryCard` — uses `AppColors.charcoal` (ink) as a
  shadow color (wrong role).
- `story_card.dart` errorBuilder — `AppColors.parchment` placeholder on a
  dark card.
- ~54 `Colors.white` across 20 files; some are legitimate (text on photo
  overlays / scrim), most are not.

**Why this priority**: The app ships `darkTheme` + a user toggle; half-dark
screens read as broken to anyone using dark mode, and every later UI change
must not re-introduce violations.

**Acceptance**:
- All widget colors route through `Theme.of(context).colorScheme` /
  `textTheme` except documented photo-overlay whites (scrim text/icons on
  images, which must carry a `// ok: on-image overlay` comment)
- `library_screen.dart` and `badge_card.dart` adapt correctly in dark mode
- A reusable dark-theme widget-test helper exists; home, stories list, story
  detail, library, login, and gamification screens each have a test pumping
  them under `AppTheme.dark` that fails if a light scaffold/background leaks

**Independent test**: `flutter test test/<feature>/` dark-mode tests green;
manual: toggle dark mode on each listed screen.

---

### User Story 2 — Text meets WCAG AA contrast (Priority: P1)

- Bronze `#C68B29` (`AppColors.ochre`) text on ivory/white ≈ **2.8:1**
  (needs 4.5:1; even 3:1 large-text bar fails): story-detail region badge +
  summary box (`story_detail_screen.dart:180-216`), `RoleBadge`
  institution-manager on light surfaces, quiz/quote small bronze labels.
- `muted #6B7280` on ivory ≈ **4.46:1** — `bodySmall` (12px) is a marginal
  AA fail on ivory (passes on white).
- `labelSmall` at **11px** with `muted` is used for metadata everywhere.

**Why this priority**: Accessibility conformance and legibility of the core
reading experience (a heritage-storytelling app whose primary content is
text).

**Acceptance**:
- `AppColors` documents semantic roles: bronze reserved for icons, borders,
  and large/bold display text (≥3:1); a new darkened bronze token
  (≥4.5:1 on ivory, e.g. `#8A5D13` range) for small accent text
- Story-detail region badge, summary, and role badges use compliant tokens
- `muted` darkened one step or `bodySmall`/`labelSmall` raised to ≥12px in
  `AppTypography`; metadata text on ivory ≥4.5:1
- Automated check: unit test asserting contrast ratio of key token pairs
  (ink/ivory, muted/ivory, accentTextStrong/ivory, textDarkMuted/surfaceDark)
  using a WCAG luminance helper

**Independent test**: `flutter test test/core/theme/` green; manual
spot-check with a contrast tool.

---

### User Story 3 — Every control is operable by screen reader (Priority: P1)

`grep Semantics` returns **0 matches** in `lib/` while there are **16
`GestureDetector`-based custom controls** with no accessible name:
like/bookmark `_StatChip` (`story_card.dart:162`), `_ActionButton` in the
reader bottom bar (like/bookmark/share — no tooltips), `_LanguageChip`,
`_RegionChip`, `_BookmarkButton`, library continue-card, audio mini-player
tap surface. Cover images (`Image.network`, `CachedNetworkImage`) have no
`semanticLabel`.

**Why this priority**: TalkBack/VoiceOver users currently get no meaningful
announcements for the app's primary interactions (like, bookmark, share,
navigate).

**Acceptance**:
- Custom tap targets converted to `IconButton(tooltip:)` / `InkWell`, or
  wrapped in `Semantics(button: true, label: …)` with a meaningful name
  (e.g. "Like, 234 likes" including state)
- Like/bookmark controls announce their current state (liked/not-liked)
- Network images carry `semanticLabel: story.title` (or equivalent)
- No bare interactive `GestureDetector` without semantics remains
  (`grep` + manual review); `Semantics` usage > 0 in `lib/`

**Independent test**: widget tests assert `Semantics` labels exist on the
story card like/bookmark and reader bottom bar; manual TalkBack pass on
stories list + reader.

---

### User Story 4 — Touch targets meet the 48dp minimum (Priority: P2)

- Like chip: 14px icon + 11px text ≈ 20px tall (`story_card.dart:158-172`)
- `_LanguageChip`: ~32px tall (`home_screen.dart:391-408`)
- `_BookmarkButton`: 8px padding + 20px icon = 36px

**Acceptance**:
- All interactive controls have ≥48×48 logical-pixel hit areas
  (`IconButton` defaults, `minimumSize`, or translucent tap behavior with
  padding)
- No visual regressions: enlarged hit areas must not change layouts (use
  transparent hit-area expansion, not bigger glyphs)

**Independent test**: widget tests assert control sizes ≥48; manual
one-handed use pass.

---

### User Story 5 — Search, filters, and dead buttons work (Priority: P2)

- **Search clear button never appears**: `_SearchBar`
  (`stories_screen.dart:318-380`) is a `StatelessWidget` reading
  `controller.text` at build time and nothing rebuilds on typing
  (`onChanged` is an empty comment).
- **Region filter is dead UI**: `_FilterChips` receives `selectedRegion`
  (used only for `hasFilters`) but renders no region chips — the filter can
  never be set from the screen. Also `ref.read(...)` inside `build` for
  filter values is a Riverpod anti-pattern (should be `ref.watch`).
- **Dead buttons**: story-detail bottom-bar Share (`// Share functionality`)
  and Take Quiz (`// Navigate to quiz`) do nothing; home `_RegionChip.onTap`
  is empty. Note: `SharingService.instance.shareStory()` already exists
  (`features/sharing/services/sharing_service.dart`).

**Why this priority**: Users see controls that visibly do nothing — erodes
trust; also the region filter silently drops a feature the provider already
implements.

**Acceptance**:
- Clear button appears/disappears reactively while typing (ListenableBuilder
  on the controller); tapping it clears text + results
- Region chips render (from a region list consistent with the API/model) and
  drive `filterByRegion`; filter values read via `ref.watch`
- Share button calls `SharingService.shareStory(...)` with the story's data;
  Take Quiz routes to the gamification quiz flow for the story (or is hidden
  behind a documented flag if no per-story quiz endpoint exists yet);
  home region tiles navigate to the stories screen pre-filtered by region
- `_buildStoryGrid`'s three near-identical masonry branches collapsed into
  one builder (loading/error banner as parameters) without behavior change

**Independent test**: widget tests for search-clear visibility + region
filter selection; `flutter analyze` green (riverpod anti-pattern removed).

---

### User Story 6 — Real EN/FR localization foundation (Priority: P2)

`app.dart` registers localization delegates and `Locale('en','fr')`, but there
is no `l10n.yaml`, no `.arb` files, no `generate: true`. The home EN/FR toggle
flips ~6 strings via a local `_isEnglish` bool; all other screens are
hardcoded English. For a bilingual (EN/FR) Cameroon heritage platform this is
a product gap.

**Acceptance**:
- `l10n.yaml` + `flutter gen-l10n` wired in `pubspec.yaml`
  (`generate: true`, `flutter_localizations` delegates from generated class)
- `.arb` files for EN + FR covering home, auth, stories list/detail, and
  library screens (the core user journey); remaining screens may follow
  incrementally but no hardcoded user-facing string remains in those five
- Home EN/FR toggle switches the app `Locale` via the settings provider (not
  a local bool); FR translations reviewed for tone
- Existing widget tests updated to not depend on English literals (or use
  the generated `AppLocalizations`)

**Independent test**: run app, toggle EN/FR in system locale → home, login,
stories, reader, library all translate; `flutter test` green.

---

### User Story 7 — Markdown rendering on a maintained package (Priority: P3)

`flutter_markdown` was discontinued by Google (April 2025); the story reader
is built on it. `flutter_markdown_plus` is the drop-in continuation.

**Acceptance**:
- `pubspec.yaml` depends on `flutter_markdown_plus`; `MarkdownBody` import
  swapped; reader renders identically (spot-check headings, blockquote,
  code, selectable text)
- `flutter analyze` + tests green

**Independent test**: `flutter test` + manual reader pass.

---

### User Story 8 — Typography scale is the single source of truth (Priority: P3)

~90 hardcoded `fontSize:` literals across video, quiz, quote, gamification,
library, sharing widgets bypass `AppTypography` (e.g. `TextStyle(fontSize: 18,
fontWeight: FontWeight.bold)` in `audio_player_sheet.dart:416,456,496`),
making text-scaling audits and redesigns impossible.

**Acceptance**:
- Widget text styles reference `Theme.of(context).textTheme` (with `copyWith`
  where needed); remaining literal sizes documented with a reason comment
- No `TextStyle(fontSize: …)` without a `textTheme` base in feature widgets
  (`grep` count → 0 unexplained)
- Text still renders sensibly at 1.3×/2.0× system font scale on stories list
  + reader (manual pass; `FittedBox` guards retained)

**Independent test**: `grep -rn "fontSize:" lib/features | wc -l` reduced to
documented exceptions; analyze + tests green.

**Coordination**: `admin_dashboard_screen.dart` is split by 001 T024 — apply
the typography sweep to admin **after** that lands.

---

### User Story 9 — Motion, scroll performance, and web shell polish (Priority: P3)

- Reader `_onScroll` calls `setState` per percent change (rebuilds whole
  screen per tick) and fires `updateProgress` on each percent — move badge
  to `ValueListenableBuilder` and debounce the progress write (e.g. every
  5% / 1s).
- `FadeSlidePageRoute` + brand-panel fades ignore
  `MediaQuery.of(context).disableAnimations` (vestibular safety).
- `web/index.html` has no `lang` attribute on `<html>`.
- Emoji-as-icon sizes (64/48px category glyphs) unreviewed at large text
  scale.

**Acceptance**:
- Reader scroll no longer rebuilds the screen per tick; progress persists at
  throttled intervals (unit-testable notifier contract)
- Transitions honor `disableAnimations` (opacity crossfade or instant)
- `web/index.html` sets `<html lang="en">`
- Large-text pass on stories list + reader shows no clipped hero/cover glyphs

**Independent test**: `flutter test` green; manual reduced-motion + 2× text
pass.

---

## Requirements

- Every change verified with `flutter analyze` (0 issues) + `flutter test`
  (0 failures) at each phase gate
- No redesign: preserve the existing visual language (tokens, spacing,
  Fraunces/PJS, indigo/bronze) — this spec enforces consistency, not a new
  look
- Follow `.agents/skills/` guidance (accessibility POUR checklist,
  flutter-use-column-row-first constraint-safety, flutter-best-practices)
- Coordinate with `001-flutter-skill-remediation`: no overlapping edits to
  `admin_dashboard_screen.dart` until 001 T024 lands; 002's `ref.watch` fix
  should precede 001 enabling `riverpod_lint` where practical

## Success Criteria

1. Dark mode correct on all screens; per-screen dark-mode widget tests guard it
2. Key text token pairs pass WCAG AA (4.5:1 body, 3:1 large) — asserted by unit test
3. `Semantics` coverage on all interactive controls; images have semantic labels
4. Interactive hit areas ≥48dp
5. Search clear, region filter, Share, Quiz, and region tiles function
6. `flutter gen-l10n` foundation live with EN + FR for the core journey
7. `flutter_markdown_plus` in place; typography literals swept; reader scroll
   throttled; reduced-motion respected; `web/index.html` has `lang`
