# Quickstart: Bottom Navigation Bar

**Date**: 2026-09-21
**Feature**: 003-bottom-navigation-bar

## Prerequisites

- Flutter SDK installed and configured
- Project dependencies resolved (`flutter pub get`)
- Device or emulator running

## Setup

```bash
# Navigate to project root
cd /home/fabiljayson/Projects/Griot_2.0/frontend

# Ensure dependencies are up to date
flutter pub get

# Run the app
flutter run
```

## Validation Scenarios

### Scenario 1: Tab Navigation (US1)

**Steps**:
1. Launch the app and log in with `admin` / `admin123`
2. Verify 5 tabs appear at the bottom: Home, Stories, Library, Gamification, Profile
3. Tap "Stories" → Stories screen loads, Stories tab is highlighted
4. Tap "Home" → Home screen loads, Home tab is highlighted
5. Tap "Library" → Library screen loads, Library tab is highlighted
6. Tap "Gamification" → Gamification screen loads, Gamification tab is highlighted
7. Tap "Profile" → Profile screen loads, Profile tab is highlighted

**Expected**: Each tab switch is instant (< 100ms), correct screen loads, active tab is highlighted in terracotta.

### Scenario 2: Tab State Preservation (US1)

**Steps**:
1. Navigate to Stories tab, scroll down
2. Switch to Home tab
3. Switch back to Stories tab

**Expected**: Scroll position is preserved — user returns to where they were.

### Scenario 3: Nested Navigation (US1)

**Steps**:
1. Navigate to Stories tab
2. Tap on a story to open detail screen
3. Press system back button

**Expected**: Returns to Stories tab (not exits the app).

### Scenario 4: Icons and Labels (US2)

**Steps**:
1. View the bottom navigation bar
2. Verify each tab has an icon and text label
3. Verify active tab has filled icon, inactive tabs have outline icons

**Expected**: All 5 tabs show icon + label, active tab is visually distinct.

### Scenario 5: Profile and Logout (US3)

**Steps**:
1. Navigate to Profile tab
2. Verify username and role are displayed
3. Tap "Logout"

**Expected**: Returns to login screen, bottom bar is hidden.

### Scenario 6: Dark Mode (US1)

**Steps**:
1. Toggle dark mode from the Home screen header
2. Verify bottom bar colors adapt (dark background, light icons)

**Expected**: Bottom bar matches dark theme.

### Scenario 7: Auth Gate (US1)

**Steps**:
1. Launch app without logging in
2. Verify bottom bar is NOT visible on login screen
3. Log in
4. Verify bottom bar appears

**Expected**: Bottom bar only shows when authenticated.

## Regression Check

```bash
# Run all tests
flutter test test/

# Run static analysis
dart analyze lib/
```

**Expected**: All 48 tests pass, 0 errors in analysis.

## Success Criteria

- [ ] 5 tabs visible and functional
- [ ] Tab switching < 100ms
- [ ] Tab state preserved across switches
- [ ] Active tab highlighted in terracotta
- [ ] Dark mode support
- [ ] Auth-gated visibility
- [ ] All existing tests pass
- [ ] No analysis errors
