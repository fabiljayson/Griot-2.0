# Tasks: Flutter Skill-Alignment Remediation

**Input**: spec.md + plan.md · **Format**: `[ID] [P?] [Story?] description`

- **[P]** = can run in parallel · **[US#]** = user story · **[P#]** = phase gate

## Phase 0 — Unblock (US1, US3)

- [ ] T001 [US1] Add missing `AppIcons` import (and Material import for `FaIcon`) to `lib/features/gamification/widgets/badge_card.dart`; `flutter analyze` = 0 issues [P0]
- [ ] T002 [US3] Run `flutter test test/widget_test.dart`, read the failure, fix root cause (test assertion drift vs app regression); full suite 26/26 [P0]

## Phase 1 — Correctness (US2, US4)

- [ ] T003 [US2] Rewrite `StoryListState.copyWith` to preserve `selectedLanguage/selectedCategory/selectedRegion` unless explicitly cleared; add `clearFilters` semantics consistent with `LibraryState.clearError` pattern [US2]
- [ ] T004 [P] [US2] Write `test/features/stories/providers/story_list_notifier_test.dart`: filter set → `loadStories` → fake repository receives filter args; `clearFilters()` wipes; pagination `hasMore` uses injected page size [US2]
- [ ] T005 [P] [US4] Extract `pre_registered_accounts.dart` passwords to `--dart-define`/git-ignored config; add `.example` file; verify `git grep -i "password:"` clean [US4]
- [ ] T006 [P0] Phase gate: `flutter analyze` 0 issues + full `flutter test` green

## Phase 2 — Error handling (US5)

- [ ] T007 [US5] Create `lib/core/network/app_error.dart`: sealed `AppFailure` + `AppErrorMapper.fromDio(DioException)`; migrate `auth_provider.dart` + `story_provider.dart` to it (delete both `_extractErrorMessage`) [US5]
- [ ] T008 [US5] Sweep all `catch (e)` blocks (video, audio, qr, library, gamification, offline_sync, error_buffer): narrow to specific types; replace "Silently fail" catches with surfaced state or `Sentry.captureException` + explanatory comment [US5]
- [ ] T009 [P0] Phase gate: analyze + tests green; `grep -rn "catch (e)" lib | wc -l` reduced to documented exceptions only

## Phase 3 — Union states (US6)

- [ ] T010 [US6] Stories: sealed `StoryListState`/`StoryDetailState` unions (initial/inProgress/ready/failure) + exhaustive switch in `stories_screen.dart`, `story_detail_screen.dart` [US6]
- [ ] T011 [P] [US6] Library + gamification notifiers → sealed unions [US6]
- [ ] T012 [P] [US6] Video + qr + audio notifiers → sealed unions; `AsyncValue.guard` in async notifiers where applicable [US6]
- [ ] T013 [P0] Phase gate: analyze + tests green per feature commit

## Phase 4 — Test coverage (US7)

- [ ] T014 [P] [US7] Provider unit tests: auth (login/register/logout/pendingSync paths) [US7]
- [ ] T015 [P] [US7] Provider unit tests: library, gamification, video status poller [US7]
- [ ] T016 [P] [US7] Widget tests: stories list (loading/error/ready/empty) + login screen [US7]
- [ ] T017 [P0] Phase gate: all feature notifiers covered; suite green

## Phase 5 — Hygiene (US8)

- [ ] T018 [US8] Inject `StoryCacheRepository` into `StoryListNotifier` via provider; replace magic `20` with `AppConstants.pageSize` [US8]
- [ ] T019 [P] [US8] `Container` → `Padding`/`DecoratedBox`/`ColoredBox` sweep (single-purpose cases only) [US8]
- [ ] T020 [P] [US8] Split `admin_dashboard_screen.dart` (1220 lines) into section widgets [US8]
- [ ] T021 [P] [US8] Add `riverpod_lint` + `custom_lint` to dev deps & `analysis_options.yaml`; fix raised lints [US8]
- [ ] T022 Final gate: re-run audit greps (sealed classes > 0, `catch (e)` documented, no password literals), `flutter analyze` + `flutter test` green; update spec.md success-criteria checkboxes

## Execution Notes

- One commit per phase; one commit per feature in Phase 3
- Do not start Phase N+1 before its predecessor's gate passes
