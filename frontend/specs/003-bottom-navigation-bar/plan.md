# Implementation Plan: Bottom Navigation Bar

**Branch**: `003-bottom-navigation-bar` | **Date**: 2026-09-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-bottom-navigation-bar/spec.md`

## Summary

Add a persistent bottom navigation bar to the Griot AI Flutter app with 5 tabs (Home, Stories, Library, Gamification, Profile). The bar provides instant access to all main sections, maintains tab state, and adapts to light/dark themes. This replaces the current ad-hoc navigation via direct `MaterialPageRoute` pushes.

## Technical Context

**Language/Version**: Dart 3.9+, Flutter 3.x

**Primary Dependencies**: flutter_riverpod (state management), flutter/material (navigation bar widgets)

**Storage**: N/A (navigation state is in-memory only)

**Testing**: flutter_test, widget tests

**Target Platform**: Android, iOS, Web, Linux, macOS, Windows

**Project Type**: mobile-app (Flutter)

**Performance Goals**: Tab switch < 100ms, zero rebuilds on unrelated state changes

**Constraints**: Must work with existing AuthWrapper for login-gated visibility; must preserve existing screen widgets without modification where possible

**Scale/Scope**: 1 new file (main_shell.dart), 2 modified files (app.dart, home_screen.dart)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Constitution file is a template (not filled in) — no specific gates to enforce.
- General Flutter best practices apply: separation of concerns, testability, performance.

## Project Structure

### Documentation (this feature)

```text
specs/003-bottom-navigation-bar/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── app.dart                          # MODIFY: Wrap with MainShell when authenticated
├── core/
│   └── navigation/
│       └── main_shell.dart           # NEW: Bottom nav bar + IndexedStack shell
├── features/
│   ├── home/
│   │   └── home_screen.dart          # MODIFY: Remove Scaffold (handled by shell)
│   ├── stories/
│   │   └── screens/
│   │       └── stories_screen.dart   # MODIFY: Remove Scaffold (handled by shell)
│   ├── library/
│   │   └── screens/
│   │       └── library_screen.dart   # MODIFY: Remove Scaffold (handled by shell)
│   ├── gamification/
│   │   └── screens/
│   │       └── gamification_screen.dart # MODIFY: Remove Scaffold (handled by shell)
│   └── auth/
│       └── screens/
│           └── profile_screen.dart    # MODIFY: Remove Scaffold (handled by shell)
```

**Structure Decision**: Single new file `main_shell.dart` in `core/navigation/` hosts the bottom bar and tab switching. Existing screen files are modified minimally to remove their individual `Scaffold` wrappers (the shell provides the Scaffold).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | — | — |
