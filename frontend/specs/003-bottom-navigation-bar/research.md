# Research: Bottom Navigation Bar

**Date**: 2026-09-21
**Feature**: 003-bottom-navigation-bar

## Decision 1: Navigation State Management

**Decision**: Use `IndexedStack` with a `StatefulWidget` holding the current tab index.

**Rationale**: `IndexedStack` preserves the state of each tab (scroll position, loaded data) when switching. This is the standard Flutter pattern for bottom navigation. Riverpod is used for cross-tab state (auth status, theme), but the tab index itself is local widget state.

**Alternatives considered**:
- `PageView`: Also preserves state but allows swiping between tabs, which may be unexpected with a bottom bar.
- GoRouter with shell route: More complex, better for deep linking. Overkill for this feature.
- Navigator 2.0: Too complex for the current app architecture.

## Decision 2: Tab Definitions

**Decision**: 5 tabs — Home, Stories, Library, Gamification, Profile.

**Rationale**: These map directly to the 5 main features of the app. The order follows user frequency: browsing (Home, Stories) → personal (Library, Gamification) → account (Profile).

**Alternatives considered**:
- 4 tabs (merge Library into Home): Loses quick access to library.
- 6 tabs (add Search): Bottom bar gets crowded; search is accessible from Stories tab.

## Decision 3: Screen Wrapping Strategy

**Decision**: Create a `MainShell` widget that provides the `Scaffold` + `BottomNavigationBar` + `IndexedStack`. Existing screens are modified to return their body content without a `Scaffold`.

**Rationale**: Centralizes the navigation shell in one place. Existing screens become pure content widgets, which is cleaner and avoids nested Scaffolds.

**Alternatives considered**:
- Keep individual Scaffolds and overlay the bottom bar: Creates visual conflicts with individual AppBars.
- Use `Navigator` push for each tab: Doesn't preserve state.

## Decision 4: Theme Integration

**Decision**: Use `AppColors.terracotta` for active tab, `AppColors.charcoalMuted` for inactive. Support dark mode via `Theme.of(context)`.

**Rationale**: Matches existing design system. The `BottomNavigationBar` widget handles light/dark theming automatically when colors are provided.

## Decision 5: Auth-Gated Visibility

**Decision**: `MainShell` is only rendered when `AuthStatus.authenticated`. The `AuthWrapper` in `app.dart` controls this.

**Rationale**: The bottom bar should never appear on login/onboarding screens. The existing `AuthWrapper` already handles this routing — we just need to ensure `MainShell` is only used as the `child` of `AuthWrapper` when authenticated.
