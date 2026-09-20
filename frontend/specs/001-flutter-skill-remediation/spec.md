# Feature Specification: Flutter Skill-Alignment Remediation

**Feature Branch**: `001-flutter-skill-remediation`

**Created**: 2026-09-20

**Status**: Approved — ready for implementation

**Input**: Audit of `griot_ai` Flutter frontend against the full `.agents/skills/`
Flutter skill set (flutter-best-practices, flutter-app-architecture,
architecture-feature-first, riverpod, effective-dart, dart-3-updates,
flutter-errors, flutter-security, flutter-testing, testing, mocktail,
code-review).

---

## Audit Verdict

**Architecture: GOOD.** The codebase already follows feature-first organization,
correct layering (View → Notifier → Repository → Service), correct Riverpod
discipline (`watch` in build / `read` in callbacks), `mounted` checks, and
controller disposal. **No re-architecture is needed.**

**Quality: CHANGES REQUESTED.** 1 broken build, 1 red test, 1 functional bug
(filters/search), ~66 unsafe catches, 6 silent error swallows, hardcoded
credentials, near-zero feature test coverage, zero sealed-class states,
no `riverpod_lint`, duplicated error-extraction logic.

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
without `?? this.…`). `StoryListNotifier.loadStories()` calls `copyWith(isLoading: true)`
**before** reading `state.selectedLanguage` — so every fetch sends `null` filters.
Active filters are visually wiped on every load.

**Acceptance**:
- copyWith preserves all fields unless explicitly cleared (explicit `clearX` flags)
- Unit test: set a filter, call `loadStories()`, assert the repository received the filter
- Unit test: `clearFilters()` clears them

**Independent test**: `flutter test test/features/stories/providers/`

---

### User Story 3 — Red widget test is fixed (Priority: P1)

`test/widget_test.dart` "App shell renders the landing screen" fails with
"Looking up a deactivated widget's ancestor is unsafe."

**Acceptance**: `flutter test` reports 26 passing / 0 failing.

**Independent test**: `flutter test test/widget_test.dart`.

---

### User Story 4 — No secrets in source control (Priority: P1)

`lib/core/constants/pre_registered_accounts.dart` contains 10 plaintext passwords
(`Visitor123!`, `Contributor123!`, `Manager123!`, `Admin2024!`, etc.) committed
to the repo.

**Acceptance**:
- Passwords no longer hardcoded; sourced from `--dart-define` or a
  git-ignored config with a checked-in `.example`
- `git grep -i "password:" lib/` returns no literals

---

### User Story 5 — Errors are handled, typed, and surfaced (Priority: P2)

~66 broad `catch (e)` blocks across the codebase; 6 swallow errors silently
(`// Silently fail for interactions`) so users and Sentry never see failures.
`_extractErrorMessage(DioException)` is duplicated in `story_provider.dart` and
`auth_provider.dart` (violates effective-dart: prefer `on SomeException`, DRY;
flutter-error-handling: structured error handling with typed failures).

**Acceptance**:
- Shared `AppFailure` (sealed: network/server/validation/offline/unknown) in
  `core/network/app_error.dart` used by all notifiers
- `AppErrorMapper.fromDio()` replaces both duplicated `_extractErrorMessage`
- Catches narrowed to `on DioException` / specific types; a broad catch only as
  documented last resort with `Error.throwWithStackTrace` → mapped failure
- Silent catches replaced with surfaced UI feedback or logged-and-reported
  (Sentry capture) with a comment stating why silence is intended

**Independent test**: analyze clean; existing tests green.

---

### User Story 6 — State modeled as explicit union types (Priority: P2)

Zero `sealed class` / `AsyncValue.guard` / union states in the codebase. State
is `bool isLoading + String? errorMessage` classes with inconsistent `copyWith`
semantics across features. The `dart-3-updates` skill requires sealed classes
for exhaustive switch handling.

**Acceptance**:
- Story list/detail, library, gamification, video, qr, audio notifiers use
  Dart 3 `sealed class` states (`initial/inProgress/ready/failure`) with
  exhaustive `switch` in views
- Auth notifier upgrades its `AuthStatus` enum to sealed-class pattern
- `AsyncValue.guard` used where an `AsyncNotifier` already applies
- One consistent copyWith policy (explicit clear flags)

**Independent test**: per-feature analyze + tests green; exhaustive switch compile-checked.

---

### User Story 7 — Feature test coverage exists (Priority: P2)

Only 4 test files exist (all admin + app shell). Per the `flutter-testing`
and `testing` skills: unit tests at the notifier/repository boundary, mirroring
`lib/` under `test/`. Use `mocktail` for mocks with `registerFallbackValue`.

**Acceptance**:
- `test/features/<feature>/providers/*_test.dart` for stories, auth, library,
  gamification, video, qr, audio
- Mocktail fakes at repository boundary; `registerFallbackValue` in `setUpAll`;
  fresh `ProviderContainer` per test
- Widget tests for stories list (loading/error/ready/empty) and login screen
- Every test can fail against broken code (no mock-only assertions)

**Independent test**: `flutter test --coverage` all green.

---

### User Story 8 — Code-hygiene sweep (Priority: P3)

- `StoryListNotifier._loadFromCache` instantiates `StoryCacheRepository()`
  directly — inject via provider (riverpod DI rule)
- `hasMore: stories.length >= 20` magic number → `AppConstants.pageSize`
- `admin_dashboard_screen.dart` is 1220 lines → split into section widgets
- Add `riverpod_lint` + `custom_lint` to `analysis_options.yaml`
- Extract duplicated `_extractErrorMessage` (covered in US5)

**Acceptance**:
- Full analyze + test suite green
- Final audit checklist re-run: sealed classes > 0, `catch (e)` documented,
  no password literals

---

## Requirements

- All fixes verified with `flutter analyze` (0 issues) + `flutter test` (0 failures)
- No behavior change beyond fixing the listed defects
- Follow project conventions already in place (feature-first, Riverpod)

## Success Criteria

1. Build green, all tests green, filters/search functionally fixed
2. No plaintext credentials in VCS
3. Every notifier uses sealed-union states with exhaustive switch
4. Shared typed error handling (`AppFailure` + `AppErrorMapper`)
5. Notifier unit tests exist for all 10 features' core providers
6. Widget tests for stories list and login screen
7. `flutter analyze` clean with `riverpod_lint` enabled
