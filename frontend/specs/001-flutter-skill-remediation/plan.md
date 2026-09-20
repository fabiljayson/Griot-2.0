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
- Lints: `flutter_lints` 6 (add `riverpod_lint` in P3)
- State: mix of `StateNotifierProvider` / `AsyncNotifierProvider` / `NotifierProvider`

## Constitution Check (from .specify/memory/constitution.md)

| Principle | Status |
|---|---|
| Feature-first organization | ✅ already satisfied — no structural moves |
| No business logic in views | ✅ spot-checked; keep invariant |
| Repositories are SSOT, injected via providers | ⚠️ `_loadFromCache` bypasses DI → US8 |
| State as explicit union types | ❌ US6 introduces them |
| Errors surfaced, never silently dropped | ❌ US5 |
| No secrets in source | ❌ US4 |
| Every PR: `flutter analyze` + `flutter test` green | ❌ US1/US3 first |

## Phases

### Phase 0 — Unblock (US1, US3) — ~30 min
1. `badge_card.dart`: add missing imports (material `FaIcon` + `AppIcons`)
2. Diagnose `widget_test.dart` failure (likely post-branding assertion drift), fix test or app defect accordingly
3. **Gate**: `flutter analyze` 0 issues, `flutter test` 26/26

### Phase 1 — Correctness (US2, US4) — ~1 h
1. Rewrite `StoryListState.copyWith` with preserve-semantics + explicit clear flags; same policy everywhere touched
2. Unit tests proving filters reach `StoryRepository` (mocktail fake repo)
3. Move `PreRegisteredAccounts` passwords out of source: `--dart-define` keys or git-ignored JSON + `.example`; document rotation need (they are already in git history)
4. **Gate**: filters unit tests green; `git grep -i "password:"` clean

### Phase 2 — Error handling (US5) — ~1–2 h
1. Add `core/network/app_error.dart`: `AppFailure` (sealed: network/server/validation/offline/unknown) + `AppErrorMapper.fromDio()`; reuse in auth + stories (delete both `_extractErrorMessage` copies)
2. Sweep the ~60 `catch (e)`: narrow to `on DioException`/`on SocketException`; replace silent catches with surfaced state or `Sentry.captureException` + comment
3. **Gate**: analyze clean; existing tests still green

### Phase 3 — Union states (US6) — ~2–3 h, feature by feature
1. Stories first (reference implementation): `sealed class StoryListState` with `initial/inProgress/ready/failure` subclasses; exhaustive `switch` in `stories_screen.dart`
2. Apply pattern to library, gamification, video, qr, audio notifiers
3. Use `AsyncValue.guard` in `AsyncNotifier`s where applicable
4. **Gate**: per-feature `analyze` + tests green before moving on

### Phase 4 — Test coverage (US7) — ~3–4 h
1. `test/` mirroring `lib/`: providers tests for stories, auth, library, gamification, video, qr, audio (mocktail fakes at repository boundary, `registerFallbackValue`, fresh `ProviderContainer` per test, `container.listen` for autoDispose)
2. Widget tests for the two most valuable screens (stories list, login)
3. **Gate**: `flutter test --coverage`, all features' core notifiers covered

### Phase 5 — Hygiene (US8) — ~1–2 h
1. Inject `StoryCacheRepository` into `StoryListNotifier`; `AppConstants.pageSize`
2. `Container` → intent widgets sweep (mechanical, verify visuals)
3. Split `admin_dashboard_screen.dart` into `_Section` widgets
4. Add `riverpod_lint` + fix new lints
5. **Gate**: full analyze + test suite green; final audit checklist re-run

## Risks

- **Credential rotation**: passwords remain valid in git history → recommend backend rotation after removal
- **copyWith change** may reveal hidden reliance on the wipe behavior → Phase 1 tests first
- **Union-state refactor** touches UI switch statements in 6 features → do one feature per commit

## Verification

After each phase: `flutter analyze && flutter test`. Final: re-run the audit
searches (sealed classes count, `catch (e)` count, `git grep password`), confirm
success criteria in spec.md.
