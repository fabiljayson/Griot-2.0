# Implementation Plan: UI Design & Frontend Remediation

**Branch**: `002-ui-frontend-remediation` · **Spec**: [spec.md](./spec.md) ·
**Created**: 2026-09-20

## Summary

Remediation plan from the UI design & frontend audit. The design system stays
as-is (Fraunces + Plus Jakarta Sans, Ndop indigo/bronze/ivory, M3) — the work
is **consistency enforcement**: route all color through the ColorScheme (dark
mode), enforce WCAG AA contrast roles, add semantics to every control, raise
tap targets, wire the dead UI, lay the gen-l10n foundation, and sweep
typography/perf/motion polish. No redesign.

## Technical Context

- Flutter 3.47.4 (verified: variable-font `fontWeight` drives the `wght`
  axis since 3.41 — the single-TTF pubspec font setup is correct; no change)
- `flutter_riverpod` 2.6; feature-first architecture (per 001 audit: keep)
- Design tokens: `core/theme/app_colors.dart` (semantic roles to be
  documented), `core/theme/app_typography.dart` (single type scale),
  `core/theme/app_theme.dart` (component themes)
- Fonts/branding: `core/widgets/brand_widgets.dart`,
  `griot_logo.dart`, `brand_pattern_painter.dart` — unchanged
- `share_plus` 13.3 already in pubspec; `SharingService.instance` exists
- i18n: `flutter_localizations` + `intl` (transitive) present; add
  `l10n.yaml` + `generate: true` (gen-l10n)

## Skills Compliance Matrix

| Principle | Skill | Status |
|---|---|---|
| Distinctive, cohesive design language; no generic AI aesthetic | `frontend-design` | ✅ already satisfied (keep) |
| Color routed through theme roles, no hardcoded light colors | `frontend-design` + M3 | ❌ Phase 1 |
| WCAG AA contrast (4.5:1 body / 3:1 large); color not sole channel | `accessibility` | ❌ Phase 2 |
| Name/role/state on every control; text alternatives for images | `accessibility` | ❌ Phase 3 |
| Target sizes ≥48dp | `accessibility` | ❌ Phase 3 |
| Constraint-safe flex layouts preserved (no new fixed/absolute hacks) | `flutter-use-column-row-first` | ✅ keep; verify per screen |
| No `ref.read` in build; reactive filter UI | `flutter-best-practices` / `riverpod` | ❌ Phase 4 |
| Localizable strings, ARB, locale-aware formatting | `inclusive-design` | ❌ Phase 5 |
| Honors reduced motion; large-text reflow | `accessibility` / `inclusive-design` | ❌ Phase 6 |
| Maintainable dependencies; single type scale | `code-review` | ❌ Phase 6 |

## Phases

### Phase 0 — Baseline & guardrails — ~30 min

1. Gate on 001 Phase 0/1 (analyze + tests green) — do not stack on a red tree
2. Add `test/helpers/pump_theme_screen.dart`: pumps a screen under
   `AppTheme.light` and `AppTheme.dark` and asserts scaffold/background is
   the expected scheme color (the M1 leak detector)
3. Record baseline grep counts (defect metrics to drive to 0):
   - `grep -rn "Colors.white" lib | wc -l` (54)
   - `grep -rn "Semantics(" lib | wc -l` (0)
   - `grep -rn "fontSize:" lib/features | wc -l` (~90)
4. **Gate [P0]**: analyze + tests green; baselines recorded in tasks.md

### Phase 1 — Dark-mode color correctness (US1) — ~2 h

1. `library_screen.dart`: Scaffold/AppBar → `colorScheme.surface` +
   `onSurface`; continue-card → `surfaceContainerHighest`; drop hardcoded
   `foregroundColor: AppColors.charcoal`
2. `badge_card.dart` `_buildFull`: `Colors.white` → scheme surface tokens
3. `home_screen.dart` `_StoryCard` shadow → `scheme.shadow` (already
   configured in ThemeData) or neutral black w/ alpha; `story_card.dart`
   errorBuilder → `scheme.surfaceContainerHighest`
4. Sweep remaining `Colors.white`/`Colors.black`/legacy aliases
   (`terracotta/ochre/parchment/charcoal`) in feature widgets → scheme
   tokens; keep only documented on-image overlays with `// ok:` comments
5. Add dark-mode pump tests for home, stories list, story detail, library,
   login, gamification (Phase 0 helper)
6. **Gate [P1]**: analyze + tests green; `Colors.white` in `lib/features`
   only on commented overlay lines

### Phase 2 — Contrast tokens (US2) — ~1–2 h

1. `app_colors.dart`: document semantic roles on each token; add
   `accentTextStrong` (darkened bronze ≥4.5:1 on ivory) and darken `muted`
   one step (≥4.5:1 on ivory); raise `labelSmall` to 12px (or drop the 11px
   style to `labelMedium`) in `app_typography.dart`
2. Story-detail region badge + summary, `role_badge.dart`,
   quiz/quote/sharing bronze text → `accentTextStrong` (bronze itself stays
   for icons/borders/large display text)
3. Add `test/core/theme/contrast_test.dart`: WCAG luminance helper +
   assertions for the key token pairs (light & dark)
4. **Gate [P2]**: theme tests green; manual contrast-tool spot-check of
   reader, role badges, quiz

### Phase 3 — Semantics & tap targets (US3, US4) — ~2–3 h

1. Story card: like/bookmark `_StatChip` + `_BookmarkButton` →
   `IconButton(tooltip:)` or `Semantics(button:, label: 'Like, N',
   selected: story.isLiked)`; hit areas ≥48 via translucent behavior
2. Reader bottom bar `_ActionButton` → labeled icon buttons (tooltip +
   Semantics incl. state); search `_LanguageChip`, home `_RegionChip`,
   mini-player tap surface → Semantics-wrapped buttons
3. Images: `semanticLabel` on `Image.network` / `CachedNetworkImage`
   (story title / artifact name) across story_card, story_detail,
   trending, library, artifact screens
4. Manual TalkBack/VoiceOver pass: stories list → reader → like → bookmark
5. **Gate [P3]**: widget tests assert labels/state on card + reader
   controls; `grep Semantics(` > 0; manual pass notes recorded

### Phase 4 — Functional UI fixes (US5) — ~2 h

1. `_SearchBar`: wrap field in `ListenableBuilder(listenable: controller)`
   so the clear button reacts; wire `onChanged` debounce (300ms) →
   `search(query)`
2. `_FilterChips`: render region chips (region list from
   `StoryModel`/API constants), drive `filterByRegion`; switch all
   `ref.read` filter values in build → `ref.watch`
3. Collapse `_buildStoryGrid`'s three duplicated masonry branches into one
   `_StoryGrid(stories:, isLoading:, banner:)`
4. Story detail: Share → `SharingService.instance.shareStory(...)`; Take
   Quiz → route to gamification quiz flow for the story (hide behind
   documented flag if per-story quiz endpoint isn't ready)
5. Home `_RegionChip.onTap` → stories screen pre-filtered by region
6. **Gate [P4]**: widget tests for search-clear + region filter; analyze +
   tests green

### Phase 5 — Localization foundation (US6) — ~3–4 h

1. Add `l10n.yaml` (gen-l10n, `nullable-getter: false`), enable
   `generate: true` in `pubspec.yaml`, swap manual delegates for the
   generated `AppLocalizations`
2. Extract EN strings to `lib/l10n/app_en.arb` (+ `app_fr.arb`) for home,
   login, register, stories list, story detail, library — the core journey;
   replace `_isEnglish` bool with a `Locale` in the settings provider
3. Translate FR copy (review tone: warm, storyteller voice; keep proverb
   strings brand-approved)
4. Update widget tests that match English literals to use
   `AppLocalizations`
5. **Gate [P5]**: app runs with EN + FR system locales; tests green;
   `grep -rn "'Trending" lib/features/home` → 0 (all via l10n) for
   covered screens

### Phase 6 — Package, typography, motion & perf polish (US7, US8, US9) — ~2–3 h

1. `flutter_markdown` → `flutter_markdown_plus` (drop-in; verify reader
   renders headings/blockquote/code/selectable identically)
2. Typography sweep in feature widgets → `textTheme` (audio sheet, quiz
   player, quote card, video sheets, trending, continue-reading);
   exceptions carry a reason comment. Apply to `admin_dashboard_screen.dart`
   only after 001 T024 split lands
3. Reader: progress badge → `ValueListenableBuilder` on a scroll-derived
   `ValueNotifier`; throttle `updateProgress` (≥5% delta or 1s)
4. Motion: `FadeSlidePageRoute` + brand fades honor
   `MediaQuery.disableAnimations` (crossfade/instant); large-text (2×)
   pass on stories list + reader
5. `web/index.html`: add `<html lang="en">`
6. Optional hygiene: `ThemeExtension` for brand gradients/tints; spacing
   constants via `brand_metrics.dart`
7. **Gate [P6]**: analyze + tests green; re-run Phase 0 grep baselines —
   `Semantics(` > 0, `fontSize:` only documented exceptions,
   `Colors.white` only commented overlays

## Risks

- **Dark-mode sweep touching many files** → one feature per commit; the
  Phase 0 pump-test harness catches leaks immediately
- **`labelSmall` 11→12px** may wrap tight metadata rows → verify story card
  + trending meta rows; `FittedBox` guards already exist on trending
- **i18n breaks widget tests** keyed on English strings → extract strings
  and update tests in the same phase (P5), after functional fixes (P4)
- **gen-l10n + hot reload friction** → run `flutter gen-l10n` via
  `generate: true` so builds stay automatic
- **flutter_markdown_plus API drift** → it's a continuation; verify
  `MarkdownStyleSheet` fields used (p/h1/h2/h3/blockquote/code) compile
- **Quiz wiring** may outpace the backend (per-story quiz) → feature-flag
  fallback documented in US5
- **Coordination with 001** → 002 P6.2 admin typography waits for 001 T024;
  002 P4 `ref.watch` fix should land before 001 enables `riverpod_lint`

## Verification

After each phase: `flutter analyze && flutter test`. Visual verification:
dark-mode toggle pass over all screens; TalkBack pass after Phase 3; EN/FR
locale pass after Phase 5; 2× text-scale + reduced-motion pass after Phase 6.
Final: re-run Phase 0 grep baselines and confirm spec.md success criteria.
