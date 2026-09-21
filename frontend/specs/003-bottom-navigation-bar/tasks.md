# Tasks: Bottom Navigation Bar

**Input**: Design documents from `/specs/003-bottom-navigation-bar/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the navigation shell structure

- [ ] T001 Create `lib/core/navigation/main_shell.dart` with `StatefulWidget` holding current tab index
- [ ] T002 Define tab configurations (icons, labels, screen widgets) as a const list in `main_shell.dart`

---

## Phase 2: User Story 1 - Persistent Navigation (Priority: P1) 🎯 MVP

**Goal**: Users can switch between 5 tabs and each tab shows the correct screen.

**Independent Test**: Launch app → verify 5 tabs → tap each → correct screen loads.

### Implementation for User Story 1

- [ ] T003 [US1] Implement `IndexedStack` in `MainShell` with 5 child screens (HomeScreen, StoriesScreen, LibraryScreen, GamificationScreen, ProfileScreen)
- [ ] T004 [US1] Add `BottomNavigationBar` widget with 5 `BottomNavigationBarItem` entries
- [ ] T005 [US1] Wire `onTap` to update `_currentIndex` state
- [ ] T006 [US1] Style active tab with `AppColors.terracotta`, inactive with `AppColors.charcoalMuted`
- [ ] T007 [US1] Wrap in `Scaffold` with `body: IndexedStack` and `bottomNavigationBar: BottomNavigationBar`

**Checkpoint**: Tab switching works, screens load, active tab is highlighted.

---

## Phase 3: User Story 2 - Tab Icons and Labels (Priority: P1)

**Goal**: Each tab has a recognizable icon and label, active tab is visually distinct.

**Independent Test**: Verify each tab shows icon + label, active tab is highlighted.

### Implementation for User Story 2

- [ ] T008 [P] [US2] Add Material icons for each tab (home, auto_stories, library_books, emoji_events, person)
- [ ] T009 [P] [US2] Add text labels below each icon
- [ ] T010 [US2] Use `selectedIcon` (filled variant) for active tab, outline for inactive
- [ ] T011 [US2] Ensure icon size and label font match Material Design guidelines (24px icon, 12px label)

**Checkpoint**: Icons and labels display correctly, active tab is visually distinct.

---

## Phase 4: User Story 3 - Profile Tab with User Info (Priority: P2)

**Goal**: Profile tab shows user info and logout option.

**Independent Test**: Tap Profile → see username/role → tap Logout → return to login.

### Implementation for User Story 3

- [ ] T012 [US3] Modify `ProfileScreen` to remove its own `Scaffold` (use `MainShell`'s Scaffold)
- [ ] T013 [US3] Ensure Profile screen reads `authProvider` for current user info
- [ ] T014 [US3] Wire logout button to call `authProvider.notifier.logout()` and trigger navigation to login

**Checkpoint**: Profile tab works, user info displays, logout returns to login screen.

---

## Phase 5: User Story 4 - Badge Indicators (Priority: P3)

**Goal**: Tabs show badge counts for pending items.

**Independent Test**: Verify badges appear when there are unread stories or pending quizzes.

### Implementation for User Story 4

- [ ] T015 [P] [US4] Add badge count support to `BottomNavigationBarItem` (use `badge` parameter or custom `Stack`)
- [ ] T016 [US4] Wire Stories tab badge to show count of unread stories from `storyListProvider`
- [ ] T017 [US4] Wire Gamification tab badge to show count of pending quizzes from `quizzesProvider`
- [ ] T018 [US4] Ensure badges hide when count is 0

**Checkpoint**: Badge indicators appear and update based on data state.

---

## Phase 6: Integration & Polish

**Purpose**: Wire the shell into the app and clean up.

- [ ] T019 [US1] Modify `lib/app.dart` to use `MainShell` as the child of `AuthWrapper` when authenticated
- [ ] T020 [US1] Modify `HomeScreen` to remove its own `Scaffold` wrapper (use shell's Scaffold)
- [ ] T021 [US1] Modify `StoriesScreen` to remove its own `Scaffold` wrapper
- [ ] T022 [US1] Modify `LibraryScreen` to remove its own `Scaffold` wrapper
- [ ] T023 [US1] Modify `GamificationScreen` to remove its own `Scaffold` wrapper
- [ ] T024 [US1] Modify `ProfileScreen` to remove its own `Scaffold` wrapper
- [ ] T025 [US1] Ensure `AppBar` titles are correct per tab (set in `MainShell` or each screen)
- [ ] T026 [US1] Test dark mode: verify tab colors adapt correctly
- [ ] T027 [US1] Test on small screens: verify icons/labels remain readable
- [ ] T028 [US1] Run `dart analyze lib/` — fix any warnings
- [ ] T029 [US1] Run `flutter test test/` — ensure all 48 tests still pass

**Checkpoint**: Full integration complete, no regressions.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (US1 - Navigation)**: Depends on Phase 1
- **Phase 3 (US2 - Icons)**: Depends on Phase 2
- **Phase 4 (US3 - Profile)**: Depends on Phase 2
- **Phase 5 (US4 - Badges)**: Depends on Phase 2
- **Phase 6 (Integration)**: Depends on all previous phases

### Within Each Phase

- Tasks marked [P] can run in parallel
- Sequential tasks must be done in order

### Parallel Opportunities

- T008 and T009 (icon + label research) can run in parallel
- T015 and T016 (badge implementations) can run in parallel
- Phases 3, 4, and 5 can run in parallel after Phase 2 completes

---

## Implementation Strategy

### MVP First (US1 + US2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Navigation shell with 5 tabs
3. Complete Phase 3: Icons and labels
4. **STOP and VALIDATE**: Tab switching works correctly
5. Proceed to Phase 6: Integration with app.dart

### Full Delivery

1. Setup → Navigation → Icons → Profile → Badges → Integration → Polish

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
