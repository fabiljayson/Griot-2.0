# African Teller — Flutter Client

Cross-platform client (Android / iOS / Web PWA) for the African Teller
digital heritage platform.

## Design system — "Ancient Manuscript"

| Token | Color | Hex |
| ----- | ----- | --- |
| Terracotta | Burnt clay red (primary) | `#C85A32` |
| Ochre | Golden savannah (secondary) | `#D99B26` |
| Savannah Green | Natural accent / success | `#2D5A27` |
| Parchment | Primary light surface | `#F4EFE6` |
| Charcoal | Ink / text | `#222222` |

Tokens live in `lib/core/theme/app_colors.dart`, with typography in
`app_typography.dart` and full `ThemeData` (light + dark) in `app_theme.dart`.

## Architecture (feature-first)

```
lib/
├── main.dart                     # Entry: Sentry init + runApp
├── app.dart                      # MaterialApp, theme, localizations
├── core/
│   ├── constants/                # App-wide constants (API base URL, etc.)
│   ├── database/                 # sqflite offline cache (Task 1.3)
│   │   ├── app_database.dart     #   schema + migrations
│   │   ├── models/               #   CachedStory
│   │   └── repositories/         #   story_cache / search_history / progress
│   ├── network/                  # Dio + smart retry (Task 4.3 foundation)
│   ├── providers/                # Riverpod providers
│   └── theme/                    # Design tokens, typography, ThemeData
└── features/                     # Feature-first modules
    ├── auth/                     # Phase 2
    ├── home/                     # Landing screen (Phase 1)
    ├── stories/                  # Phase 3
    ├── audio/ video/             # Phase 4
    ├── qr_scanner/               # Phase 5
    ├── gamification/             # Phase 6
    ├── library/ sharing/         # Phases 7–8
```

## State management

Riverpod (`flutter_riverpod`) — providers live in `lib/core/providers/` and
feature-local providers next to their features.

## Run

```bash
cd frontend
flutter pub get
flutter run -d chrome      # web
flutter run                # connected device / emulator
```

Point the app at a local backend:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Offline cache (Task 1.3)

Mobile builds use sqflite (`lib/core/database/`). The web client replaces
sqflite with IndexedDB in Phase 9. Tables:

- `story_cache` — stories saved for offline reading
- `search_history` — local search history for fuzzy search suggestions
- `reading_progress` — scroll depth + audio resume timestamps
