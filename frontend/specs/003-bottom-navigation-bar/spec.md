# Feature Specification: Bottom Navigation Bar

**Feature Branch**: `003-bottom-navigation-bar`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Add a bottom navigation bar with Home, Stories, Library, Gamification, and Profile tabs to the Griot AI Flutter app"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Persistent Navigation Across Features (Priority: P1)

As a user, I want a persistent bottom navigation bar so that I can quickly switch between the main sections of the app (Home, Stories, Library, Gamification, Profile) without losing my place or navigating through multiple screens.

**Why this priority**: This is the foundational UX improvement — without it, users must use the back button or re-launch screens manually. Every other feature depends on easy navigation.

**Independent Test**: Can be fully tested by launching the app, verifying 5 tabs appear at the bottom, and tapping each tab to confirm the correct screen loads.

**Acceptance Scenarios**:

1. **Given** the user is on the Home screen, **When** they tap the "Stories" tab, **Then** the Stories screen loads and the Stories tab is highlighted.
2. **Given** the user is on the Gamification screen, **When** they tap the "Home" tab, **Then** the Home screen loads and the Home tab is highlighted.
3. **Given** the user has navigated to a story detail screen from the Stories tab, **When** they press the system back button, **Then** they return to the Stories tab (not退出 the app).
4. **Given** the user is on any tab, **When** they tap the currently active tab, **Then** the screen scrolls to the top (or no action if already at top).

---

### User Story 2 - Tab Icons and Labels (Priority: P1)

As a user, I want each tab to have a recognizable icon and label so that I can quickly identify which section I'm in and where to navigate.

**Why this priority**: Icons and labels are essential for usability — without them, the navigation bar is meaningless.

**Independent Test**: Can be tested by verifying each tab displays an icon and label, and the active tab is visually distinct.

**Acceptance Scenarios**:

1. **Given** the bottom navigation bar is visible, **When** the user views it, **Then** each of the 5 tabs shows an icon and a text label.
2. **Given** the user is on the Stories tab, **When** they view the bottom bar, **Then** the Stories tab icon and label are highlighted in the primary color.
3. **Given** the user switches tabs, **When** the transition occurs, **Then** the previous tab deselects and the new tab selects with a smooth visual transition.

---

### User Story 3 - Profile Tab with User Info (Priority: P2)

As a user, I want the Profile tab to show my account information and allow me to log out, so that I can manage my profile without navigating away from the main app flow.

**Why this priority**: Profile access is a common need but less frequent than browsing stories.

**Independent Test**: Can be tested by tapping the Profile tab, verifying user info displays, and confirming logout works.

**Acceptance Scenarios**:

1. **Given** the user is authenticated, **When** they tap the Profile tab, **Then** their username, role, and profile options are displayed.
2. **Given** the user is on the Profile tab, **When** they tap "Logout", **Then** they are returned to the login screen and the bottom bar is hidden.

---

### User Story 4 - Badge Indicators on Tabs (Priority: P3)

As a user, I want to see badge counts on tabs (e.g., pending quizzes, new stories) so that I know when there's something new to check.

**Why this priority**: Nice-to-have for engagement but not essential for core navigation.

**Independent Test**: Can be tested by verifying badge indicators appear when there are pending items.

**Acceptance Scenarios**:

1. **Given** there are unread stories, **When** the user views the bottom bar, **Then** a badge count appears on the Stories tab.
2. **Given** there are pending quizzes, **When** the user views the bottom bar, **Then** a badge count appears on the Gamification tab.

---

### Edge Cases

- What happens when the user is on a nested screen (e.g., story detail) and taps a different tab? → Should switch to that tab's root screen.
- What happens when the user logs out? → Bottom bar should hide completely.
- What happens on very small screens? → Icons and labels should still be readable; consider hiding labels on very small screens.
- What happens when the app is in dark mode? → Tab colors should adapt to the dark theme.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a bottom navigation bar with 5 tabs: Home, Stories, Library, Gamification, Profile.
- **FR-002**: System MUST highlight the currently active tab with the primary color.
- **FR-003**: System MUST persist the selected tab across screen rebuilds (e.g., after hot reload).
- **FR-004**: System MUST navigate to the root screen of each tab when a tab is tapped.
- **FR-005**: System MUST hide the bottom bar when the user is not authenticated (login/onboarding screens).
- **FR-006**: System MUST use the existing theme colors (terracotta for active, muted for inactive).
- **FR-007**: System MUST support both light and dark themes.
- **FR-008**: System MUST maintain tab state (scroll position) when switching between tabs.
- **FR-009**: System MUST use Material Design navigation bar conventions (selected/unselected icon styles).
- **FR-010**: System MUST provide haptic feedback on tab switch (optional but recommended).

### Key Entities

- **NavigationTab**: Represents a tab with icon, label, and associated screen widget.
- **TabState**: Tracks the current active tab index and maintains per-tab navigation state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch between any two tabs in under 1 second.
- **SC-002**: 100% of main screens are accessible within 1 tap from any screen.
- **SC-003**: Tab switching maintains scroll position — users don't lose their place.
- **SC-004**: The navigation bar adapts correctly to both light and dark themes.
- **SC-005**: No navigation-related crashes or errors during normal use.

## Assumptions

- The app currently has no bottom navigation bar — all navigation is via direct `MaterialPageRoute` pushes.
- The existing screens (HomeScreen, StoriesScreen, LibraryScreen, GamificationScreen, ProfileScreen) will be wrapped as tab root screens.
- The app uses Flutter's `IndexedStack` or equivalent to maintain tab state.
- The existing theme system (AppColors, AppTheme) will be reused for tab styling.
- The AuthWrapper will control bottom bar visibility based on authentication state.
