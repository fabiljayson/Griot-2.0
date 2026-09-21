# Data Model: Bottom Navigation Bar

**Date**: 2026-09-21
**Feature**: 003-bottom-navigation-bar

## Entities

### NavigationTab (Enum/Constant)

Represents a single tab in the bottom navigation bar.

| Field | Type | Description |
|-------|------|-------------|
| index | int | Position in the bottom bar (0-4) |
| icon | IconData | Material icon for the tab |
| selectedIcon | IconData | Filled variant when active |
| label | String | Text label below the icon |
| screen | Widget | The root screen widget for this tab |

### Tab navigation order:

| Index | Tab | Icon | Screen |
|-------|-----|------|--------|
| 0 | Home | home | HomeScreen |
| 1 | Stories | auto_stories | StoriesScreen |
| 2 | Library | library_books | LibraryScreen |
| 3 | Gamification | emoji_events | GamificationScreen |
| 4 | Profile | person | ProfileScreen |

### MainShellState (Internal Widget State)

| Field | Type | Description |
|-------|------|-------------|
| _currentIndex | int | Currently selected tab index (default: 0) |
| _pageCache | Map<int, Widget> | Cached page widgets per tab |

## State Transitions

```
[Login Screen] → (auth success) → [MainShell with Home tab selected]
[MainShell] → (tap tab) → [MainShell with new tab selected, previous tab state preserved]
[MainShell] → (tap Profile → Logout) → [Login Screen, MainShell disposed]
```

## No Database Changes Required

Navigation state is ephemeral (in-memory only). No new SQLite tables needed.
