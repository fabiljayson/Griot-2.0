# Implementation Plan: Flutter Skill-Alignment Remediation

**Branch**: `001-flutter-skill-remediation` · **Spec**: [spec.md](./spec.md) · **Created**: 2026-09-20

## Summary

Remediation plan from the skills-based audit. Architecture stays as-is
(feature-first, Riverpod, MVVM layering is already correct). Work is
defect-fixing first (build, red test, filter bug, secrets), then error-handling
and state-modeling alignment with the skills, then test coverage, then hygiene.

## Technical Context

- Flutter 3.x, Dart SDK ^3.9.0, `flutter_riverpod` + `hooks_riverpod` 2.6
- Backend: Django/DRF via Dio (`ApiClient` singleton + interceptors), sqflite offline cache
- Lints: `flutter_lints` 6 (add `riverpod_lint` in Phase 5)
- State: mix of `StateNotifierProvider` / `AsyncNotifierProvider` / `NotifierProvider`
- Skills: 10 Flutter/Dart skills from `.agents/skills/` govern all patterns

## Skills Compliance Matrix

| Principle | Skill | Status |
|---|---|---|
| Feature-first organization | `architecture-feature-first` | ✅ already satisfied |
| No business logic in views | `flutter-best-practices` | ✅ spot-checked |
| Repositories are SSOT, injected via providers | `riverpod` | ⚠️ `_loadFromCache` bypasses DI → Phase 5 |
| State as explicit union types (sealed) | `dart-3-updates` + `flutter-best-practices` | ❌ Phase 3 |
| Errors surfaced, never silently dropped | `flutter-error-handling` | ❌ Phase 2 |
| No secrets in source | `flutter-security` | ❌ Phase 1 |
| Typed failures (sealed AppFailure) | `flutter-error-handling` | ❌ Phase 2 |
| Tests mirror lib/ structure | `flutter-testing` + `testing` | ❌ Phase 4 |
| mocktail for mocking | `mocktail` | ❌ Phase 4 (add dep) |
| riverpod_lint enabled | `riverpod` | ❌ Phase 5 |
| Every PR: analyze + test green | ALL | ❌ Phase 0 first |

## Phases

### Phase 0 — Unblock (US1, US3) — ~30 min

1. `badge_card.dart`: add missing imports (already fixed — verify)
2. Diagnose `widget_test.dart` failure (deactivated widget ancestor lookup), fix root cause
3. **Gate**: `flutter analyze` 0 issues, `flutter test` 26/26

### Phase 1 — Security & Correctness (US2, US4) — ~1 h

1. Move `PreRegisteredAccounts` passwords out of source: `--dart-define` keys or git-ignored JSON + `.example`; document rotation need
2. Rewrite `StoryListState.copyWith` with preserve-semantics + explicit clear flags
3. Unit tests proving filters reach `StoryRepository` (mocktail fake repo)
4. **Gate**: `git grep -i "password:" lib/` clean; filter tests green

### Phase 2 — Error Handling (US5) — ~1–2 h

1. Add `core/network/app_error.dart`: sealed `AppFailure` (network/server/validation/offline/unknown) + `AppErrorMapper.fromDio()`; reuse in auth + stories (delete both `_extractErrorMessage` copies)
2. Sweep the ~66 `catch (e)`: narrow to `on DioException`/`on SocketException`; replace silent catches with surfaced state or `Sentry.captureException` + comment
3. **Gate**: analyze clean; existing tests still green

### Phase 3 — Union States (US6) — ~2–3 h, feature by feature

1. Stories first (reference implementation): `sealed class StoryListState` with `initial/inProgress/ready/failure` subclasses; exhaustive `switch` in `stories_screen.dart`, `story_detail_screen.dart`
2. Apply pattern to library, gamification, video, qr, audio notifiers
3. Upgrade auth notifier `AuthStatus` enum to sealed-class pattern
4. Use `AsyncValue.guard` in `AsyncNotifier`s where applicable
5. **Gate**: per-feature `analyze` + tests green before moving on

### Phase 4 — Test Coverage (US7) — ~3–4 h

1. `test/` mirroring `lib/`: providers tests for stories, auth, library, gamification, video, qr, audio (mocktail fakes at repository boundary, `registerFallbackValue` in `setUpAll`, fresh `ProviderContainer` per test, `container.listen` for autoDispose)
2. Widget tests for the two most valuable screens (stories list, login)
3. Add `mocktail` to `dev_dependencies` if not present
4. **Gate**: `flutter test --coverage`, all features' core notifiers covered

### Phase 5 — Hygiene (US8) — ~1–2 h

1. Inject `StoryCacheRepository` into `StoryListNotifier` via provider; replace magic `20` with `AppConstants.pageSize`
2. Split `admin_dashboard_screen.dart` (1220 lines) into section widgets
3. Add `riverpod_lint` + `custom_lint` to dev deps & `analysis_options.yaml`; fix raised lints
4. **Gate**: full analyze + test suite green; final audit checklist re-run

## Risks

- **Credential rotation**: passwords remain valid in git history → recommend backend rotation after removal
- **copyWith change** may reveal hidden reliance on the wipe behavior → Phase 1 tests first
- **Union-state refactor** touches UI switch statements in 8 features → do one feature per commit
- **No `mocktail` in pubspec** → add in Phase 4 before writing tests

## Verification

After each phase: `flutter analyze && flutter test`. Final: re-run the audit
searches (sealed classes count, `catch (e)` count, `git grep password`),
confirm success criteria in spec.md.
