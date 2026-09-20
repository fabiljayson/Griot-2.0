# Tasks: UI Design & Frontend Remediation

**Input**: spec.md + plan.md · **Format**: `[ID] [P?] [Story?] description`

- **[P]** = can run in parallel · **[US#]** = user story · **[P#]** = phase gate

## Phase 0 — Baseline & guardrails

- [ ] T001 [US1] Create `test/helpers/pump_theme_screen.dart` dark/light pump
      helper asserting scaffold background matches the active scheme
      [P0]
- [ ] T002 Record defect baselines in this file: `Colors.white` in
      lib/features (54), `Semantics(` count (0), `fontSize:` in
      lib/features (~90) [P0]
- [ ] T003 [P0] Phase gate: `flutter analyze` 0 issues + `flutter test` green

## Phase 1 — Dark-mode color correctness (US1)

- [ ] T004 [US1] `library_screen.dart`: Scaffold/AppBar/cards → scheme
      tokens (surface, surfaceContainerHighest, onSurface); remove
      hardcoded `parchment`/`charcoal`/`Colors.white` [P1]
- [ ] T005 [US1] `badge_card.dart` `_buildFull`: `Colors.white` → scheme
      surface tokens [P1]
- [ ] T006 [P] [US1] `home_screen.dart` `_StoryCard` shadow → `scheme.shadow`;
      `story_card.dart` errorBuilder → `surfaceContainerHighest` [P1]
- [ ] T007 [P] [US1] Sweep remaining `Colors.white/black` + legacy aliases
      (`terracotta/ochre/parchment`) in feature widgets → scheme tokens;
      keep only documented on-image overlays with `// ok:` comments [P1]
- [ ] T008 [US1] Dark-mode pump tests (Phase 0 helper) for home, stories
      list, story detail, library, login, gamification [P1]
- [ ] T009 [P1] Phase gate: analyze + tests green; `Colors.white` in
      lib/features only on commented overlay lines

## Phase 2 — Contrast tokens (US2)

- [ ] T010 [US2] `app_colors.dart`: document semantic roles; add
      `accentTextStrong` (darkened bronze ≥4.5:1 on ivory); darken `muted`
      ≥4.5:1 on ivory; `app_typography.dart`: `labelSmall` 11px → 12px [P2]
- [ ] T011 [US2] Story-detail region badge + summary, `role_badge.dart`,
      quiz/quote/sharing bronze text → `accentTextStrong` [P2]
- [ ] T012 [P] [US2] `test/core/theme/contrast_test.dart`: WCAG luminance
      helper + assertions for ink/ivory, muted/ivory,
      accentTextStrong/ivory, textDarkMuted/surfaceDark [P2]
- [ ] T013 [P2] Phase gate: theme tests green; contrast spot-check of
      reader, role badges, quiz

## Phase 3 — Semantics & tap targets (US3, US4)

- [ ] T014 [US3] Story card: like/bookmark `_StatChip` + `_BookmarkButton`
      → `IconButton(tooltip:)` / `Semantics(button:, label: 'Like, N',
      selected: isLiked)` [P3]
- [ ] T015 [US3] Reader bottom bar `_ActionButton` → labeled icon buttons
      with state semantics; search `_LanguageChip`, home `_RegionChip`,
      mini-player surface → Semantics-wrapped buttons [P3]
- [ ] T016 [P] [US3] `semanticLabel` on `Image.network` /
      `CachedNetworkImage` across story_card, story_detail, trending,
      library, artifact screens [P3]
- [ ] T017 [US4] Enlarge hit areas to ≥48dp (translucent tap behavior /
      `IconButton` minimums) on story-card stats, `_LanguageChip`,
      `_BookmarkButton` — no visual size regressions [P3]
- [ ] T018 [P3] Phase gate: widget tests assert labels/state on card +
      reader controls; `Semantics(` > 0; manual TalkBack pass recorded

## Phase 4 — Functional UI fixes (US5)

- [ ] T019 [US5] `_SearchBar`: `ListenableBuilder` on controller so the
      clear button reacts; 300ms debounce `onChanged` → `search(query)` [P4]
- [ ] T020 [US5] `_FilterChips`: render region chips driving
      `filterByRegion`; replace `ref.read` filter values in build with
      `ref.watch` [P4]
- [ ] T021 [US5] Collapse `_buildStoryGrid`'s three duplicated masonry
      branches into one `_StoryGrid(stories:, isLoading:, banner:)` [P4]
- [ ] T022 [US5] Story detail: Share → `SharingService.instance.shareStory(...)`;
      Take Quiz → gamification quiz flow for the story (feature-flagged if
      the per-story quiz endpoint isn't ready) [P4]
- [ ] T023 [P] [US5] Home `_RegionChip.onTap` → stories screen pre-filtered
      by region; regions from model/API constants, not a hardcoded list [P4]
- [ ] T024 [P4] Phase gate: widget tests for search-clear + region filter;
      analyze + tests green

## Phase 5 — Localization foundation (US6)

- [ ] T025 [US6] Add `l10n.yaml` + `generate: true` in pubspec; swap manual
      delegates for generated `AppLocalizations` [P5]
- [ ] T026 [US6] Extract EN strings to `lib/l10n/app_en.arb` (+ `app_fr.arb`)
      for home, login, register, stories list, story detail, library;
      replace `_isEnglish` bool with a `Locale` in settings provider [P5]
- [ ] T027 [P] [US6] FR translations reviewed for storyteller tone; proverb
      strings brand-approved [P5]
- [ ] T028 [US6] Update widget tests matching English literals to use
      `AppLocalizations` [P5]
- [ ] T029 [P5] Phase gate: EN + FR system locales render the core journey;
      tests green; no hardcoded user-facing strings on covered screens

## Phase 6 — Package, typography, motion & perf polish (US7, US8, US9)

- [ ] T030 [US7] `flutter_markdown` → `flutter_markdown_plus`; verify
      reader headings/blockquote/code/selectable render identically [P6]
- [ ] T031 [US8] Typography sweep in feature widgets (audio sheet, quiz
      player, quote card, video sheets, trending, continue-reading) →
      `textTheme`; exceptions carry a reason comment. Admin dashboard only
      after 001 T024 lands [P6]
- [ ] T032 [US9] Reader progress badge → `ValueListenableBuilder`;
      throttle `updateProgress` (≥5% delta or 1s) [P6]
- [ ] T033 [P] [US9] `FadeSlidePageRoute` + brand fades honor
      `MediaQuery.disableAnimations`; 2× text-scale pass on stories list +
      reader [P6]
- [ ] T034 [P] [US9] `web/index.html`: add `<html lang="en">` [P6]
- [ ] T035 [P] [US9] Optional hygiene: `ThemeExtension` for brand gradients/
      tints; spacing constants via `brand_metrics.dart` [P6]
- [ ] T036 Final gate: analyze + tests green; re-run T002 baselines —
      `Semantics(` > 0, `fontSize:` only documented exceptions,
      `Colors.white` only commented overlays; tick spec.md success criteria

## Execution Notes

- One commit per phase; dark-mode sweep (T007) one feature per commit
- Do not start Phase N+1 before its predecessor's gate passes
- i18n (Phase 5) after functional fixes (Phase 4) so extracted strings are
  final; widget-test string updates happen in the same phase
- Skills referenced: frontend-design, accessibility, inclusive-design,
  flutter-best-practices, flutter-use-column-row-first, code-review
