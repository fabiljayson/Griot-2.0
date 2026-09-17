# Griot AI — Digital Heritage Platform

> *A griot (ˈɡriː.oʊ) is a West African storyteller, praise-singer, and keeper of oral history.*

Cross-platform digital heritage platform (Android / iOS / Web PWA) for preserving and sharing Cameroon's oral traditions. Read cultural tales, scan museum artifact QR codes, and earn heritage badges.

**Backend:** Django REST Framework API

## Features

- **📖 Stories & Storytelling** — Digital library of cultural tales with multi-language support (EN, FR, Fulfulde, Duala, Ewondo, Bamileke)
- **📱 Offline-First** — Read stories, cache content, and sync when back online
- **🎫 QR Code Scanner** — Scan museum artifact codes for immersive digital experiences
- **🎵 Audio Narration** — AI-generated text-to-speech for stories
- **🎬 AI Video Generation** — Luma AI-powered story videos
- **🏆 Gamification** — Quizzes, badges, leaderboards, and heritage certificates
- **🌐 Social Sharing** — Share quotes and stories across platforms
- **👨‍💼 Admin Dashboard** — Analytics, moderation, and content management

## Design System — "African Heritage"

| Token | Color | Usage |
| ----- | ----- | ----- |
| Terracotta | `#C84C09` | Primary brand, CTAs, interactive elements |
| Ochre | `#D99B22` | Secondary accent, highlights |
| Savannah Green | `#5B7040` | Success, tertiary accent |
| Sand | `#F9F5F0` | Light mode background |
| Deep Earth | `#2C241B` | Light mode text |
| Mud Charcoal | `#1A1512` | Dark mode background |

**Typography:**
- Headlines: Fraunces (warm, storytelling serif)
- Body/UI: Plus Jakarta Sans

Design tokens live in:
- `lib/core/theme/app_colors.dart` — Color palette
- `lib/core/theme/app_typography.dart` — Text styles
- `lib/core/theme/app_theme.dart` — Full ThemeData (light + dark)
- `lib/core/theme/app_icons.dart` — Font Awesome icon set

## Architecture (Feature-First)

```
lib/
├── main.dart                          # Entry point, Sentry init
├── app.dart                           # MaterialApp, theme, localizations
├── core/
│   ├── constants/                     # app_constants, pre_registered_accounts
│   ├── database/                      # SQLite (mobile), models, repositories
│   ├── navigation/                    # Custom page transitions
│   ├── network/                       # Dio client, auth interceptor, offline sync
│   ├── offline/                       # Offline provider, error buffer
│   ├── providers/                     # Riverpod providers
│   ├── theme/                         # Colors, typography, themes, icons
│   └── widgets/                       # GriotMark logo, shared widgets
└── features/
    ├── admin/                         # Dashboard, analytics, moderation
    ├── audio/                         # TTS, audio player
    ├── auth/                          # Login, register, onboarding, profile
    ├── gamification/                  # Quizzes, badges, leaderboard
    ├── home/                          # Home screen, connectivity widget
    ├── library/                       # Continue reading, bookmarks
    ├── qr_scanner/                    # QR scanner, artifact detail
    ├── sharing/                       # Share button, quote card, trending
    ├── stories/                       # Story list, detail, form
    └── video/                         # Video generation, player
```

## State Management

Riverpod (`flutter_riverpod`) — providers live in `lib/core/providers/` and feature-local providers next to their features.

## Getting Started

### Prerequisites

- Flutter SDK ^3.12.0
- Dart SDK ^3.12.0
- Backend API running (see `../backend/`)

### Installation

```bash
cd frontend
flutter pub get
```

### Running

```bash
# Web
flutter run -d chrome

# Mobile (connected device / emulator)
flutter run

# With custom backend URL
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# With Ngrok tunnel (physical device testing)
flutter run --dart-define=NGROK_URL=https://xxxx-xx-xx-xx-xx.ngrok-free.app
```

## Project Structure

### Frontend (`frontend/`)
- **Platform:** Android, iOS, Web (PWA)
- **State:** Riverpod
- **Network:** Dio with interceptors
- **Database:** sqflite (mobile) / IndexedDB via `sqflite_common_ffi_web` (web)
- **Theme:** Custom African heritage palette

### Backend (`backend/`)
- **Framework:** Django REST Framework
- **Auth:** JWT (access + refresh tokens)
- **Database:** SQLite (dev) / PostgreSQL (prod)
- **API:** RESTful with OpenAPI documentation

## Offline-First Architecture

Mobile builds use sqflite (`lib/core/database/`); on web, `main()` swaps in
the `sqflite_common_ffi_web` factory so the same tables live in IndexedDB.
Tables:

- `story_cache` — Stories saved for offline reading
- `search_history` — Local search history
- `reading_progress` — Scroll depth + audio resume timestamps
- `offline_requests` — Queued API calls for retry
- `offline_users` — Queued user registrations

## Key Features

### Authentication
- JWT access + refresh tokens (30 min access, 7 day refresh)
- 4-tier RBAC: Visitor → Contributor → Institution Manager → Admin
- Social login support (Google, Apple)
- Onboarding screen on first launch

### Stories
- Multi-language support (EN, FR, Fulfulde, Duala, Ewondo, Bamileke)
- Markdown reader with reading progress tracking
- Story categories with emoji icons
- Region filtering
- Search & discovery with fuzzy text search

### QR Codes & Museums
- In-app QR code scanner
- Digital artifact catalog
- Deep linking for shared content
- Scan tracking with device info

### Gamification
- Multiple-choice quizzes per story
- XP system with level progression
- Achievement badges across categories
- Leaderboard and heritage certificates

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `API_BASE_URL` | Backend API base URL |
| `NGROK_URL` | Ngrok tunnel URL for physical device testing |
| `SENTRY_DSN` | Sentry error monitoring DSN |

## License

Private project — All rights reserved.

---

*Built with ❤️ for preserving Africa's oral traditions*
