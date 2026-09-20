# Feature Specification: Flutter Skill-Alignment Remediation

**Feature Branch**: `001-flutter-skill-remediation`

**Created**: 2026-09-20

**Status**: Draft — awaiting user approval

**Input**: Audit of `griot_ai` Flutter frontend against the newly imported
`.agents/skills` Flutter skill set (flutter-best-practices, flutter-app-architecture,
architecture-feature-first, riverpod, effective-dart, dart-3-updates, flutter-errors,
testing, mocktail, code-review).

---

## Audit Verdict

**Architecture: GOOD.** The codebase already follows feature-first organization,
correct layering (View → Notifier → Repository → Service), correct Riverpod
discipline (`watch` in build / `read` in callbacks), `mounted` checks, and
controller disposal. **No re-architecture is needed.**

**Quality: CHANGES REQUESTED.** 1 broken build, 1 red test, 1 functional bug
(filters/search), ~60 unsafe catches, hardcoded credentials, near-zero feature
test coverage.

---

## User Scenarios & Testing

### User Story 1 — Build is green again (Priority: P1)

`lib/features/gamification/widgets/badge_card.dart` references `FaIcon` and
`AppIcons` without the required imports → **6 analyzer errors, `flutter build` fails**.

**Why this priority**: Nothing else can be verified while the build is broken.

**Acceptance**:
- `flutter analyze` reports 0 issues
- `flutter test` passes

**Independent test**: run `flutter analyze` → 0 errors.

---

### User Story 2 — Story filters and search actually reach the API (Priority: P1)

`StoryListState.copyWith` unconditionally resets `selectedLanguage`,
`selectedCategory`, `selectedRegion` (lines: `selectedLanguage: selectedLanguage,`
without `?? this.…`). `StoryListNotifier.loadStories()` calls `copyWith(isLoading:
true)` **before** reading `state.selectedLanguage` — so every fetch sends
`null` filters. Active filters are visually wiped on every load.

**Acceptance**:
- copyWith preserves all fields unless explicitly cleared (explicit `clearX` flags)
- Unit test: set a filter, call `loadStories()`, assert the repository received the filter
- Unit test: `clearFilters()` clears them

**Independent test**: `flutter test test/features/stories/providers/`

---

### User Story 3 — Red widget test is fixed (Priority: P1)

`test/widget_test.dart` "App shell renders the landing screen" fails.

**Acceptance**: `flutter test` reports 26 passing / 0 failing.

**Independent test**: `flutter test test/widget_test.dart`.

---

### User Story 4 — No secrets in source control (Priority: P1)

`lib/core/constants/pre_registered_accounts.dart` contains plaintext passwords
(`Visitor123!`, etc.) committed to the repo.

**Acceptance**:
- Passwords no longer hardcoded; sourced from `--dart-define` or a
  git-ignored config with a checked-in `.example`
- `git grep -i "password:" lib/` returns no literals

---

### User Story 5 — Errors are handled, typed, and surfaced (Priority: P2)

~60 broad `catch (e)` blocks; several swallow errors silently
(`// Silently fail for interactions`) so users and Sentry never see failures.
`_extractErrorMessage(DioException)` is duplicated in `story_provider.dart` and
`auth_provider.dart` (violates effective-dart: prefer `on SomeException`,
DRY; dart-coding-practices: structured error handling).

**Acceptance**:
- Shared `AppErrorMapper`/`AppFailure` in `core/network/` used by all notifiers
- Catches narrowed to `on DioException` / specific types; a broad catch only as
  documented last resort with `Error.throwWithStackTrace` → mapped failure
- Silent catches replaced with surfaced UI feedback or logged-and-reported
  (Sentry capture) with a comment stating why silence is intended

---

### User Story 6 — State modeled as explicit union types (Priority: P2)

Zero `sealed class` / `AsyncValue.guard` / union states in the codebase. State
is `bool isLoading + String? errorMessage` classes with inconsistent `copyWith`
semantics across features (some clear, some keep, one has a `clearError` flag).

**Acceptance**:
- Story list/detail, library, gamification, video, qr, audio notifiers use
  Dart 3 `sealed class` states (`initial/inProgress/ready/failure`) with
  exhaustive `switch` in views
- `AsyncValue.guard` used where an `AsyncNotifier` already applies
- One consistent copyWith policy (explicit clear flags)

---

### User Story 7 — Feature test coverage exists (Priority: P2)

Only 4 test files exist (all admin + app shell). Per the `testing` skill:
unit tests at the notifier/repository boundary, mirroring `lib/` under `test/`.

**Acceptance**:
- `test/features/<feature>/providers/*_test.dart` for stories, auth, library,
  gamification (mocktail fakes at repository boundary; `registerFallbackValue`
  in `setUpAll`; fresh `ProviderContainer` per test)
- Every test can fail against broken code (no mock-only assertions)

---

### User Story 8 — Code-hygiene sweep (Priority: P3)

- `StoryListNotifier._loadFromCache` instantiates `StoryCacheRepository()`
  directly — inject via provider (DI rule)
- `hasMore: stories.length >= 20` magic number → `AppConstants.pageSize`
- 130 `Container(` usages → convert obvious single-purpose cases to
  `Padding`/`DecoratedBox`/`ColoredBox` (sweep, keep legitimate combos)
- `admin_dashboard_screen.dart` is 1220 lines → split into section widgets
- Add `riverpod_lint` + `custom_lint` to `analysis_options.yaml`
- Extract duplicated `_extractErrorMessage` (covered in US5)

---

## Requirements

- All fixes verified with `flutter analyze` (0 issues) + `flutter test` (0 failures)
- No behavior change beyond fixing the listed defects
- Follow project conventions already in place (feature-first, Riverpod)

## Success Criteria

1. Build green, all tests green, filters/search functionally fixed
2. No plaintext credentials in VCS
3. Every notifier either sealed-union state or documented exception
4. Notifier unit tests exist for all 10 features' core providers
5. `flutter analyze` clean with `riverpod_lint` enabled
