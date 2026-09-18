# Griot 2.0 — African Teller

A cross-platform digital heritage platform preserving and sharing Cameroon's
oral traditions. Read cultural tales, scan museum artifact QR codes, watch
AI-generated story videos, quiz your knowledge, and earn heritage badges.

> _A griot (ˈɡriː.oʊ) is a West African storyteller, praise-singer, and keeper
> of oral history._

## Features

- **Cultural Stories** — Digital library of oral traditions from Cameroon
- **Museum Artifacts** — QR code system for museum visitor engagement
- **AI Media** — Text-to-speech narration and AI-generated story videos
- **Gamification** — Quizzes, badges, XP system, and certificates
- **Offline-First** — Read stories and listen to audio without internet
- **Multi-Language** — English, French, and local Cameroonian languages

## Color Palette

The platform uses a **Cameroonian heritage-inspired** color system:

| Color | Name | Usage |
|-------|------|-------|
| 🟦 | `cam-indigo` (#1E2B58) | Primary headers, navigation |
| 🟨 | `cam-bronze` (#C68B29) | CTAs, active states, audio controls |
| 🟥 | `cam-earth` (#A0382B) | Historical alerts, badges |
| 🟩 | `cam-green` (#1B4332) | Success states, location tags |
| ⬜ | `cam-ivory` (#FBF9F4) | Background canvas |
| ⬜ | `cam-white` (#FFFFFF) | Cards, surfaces |

## Repo layout

```
├── backend/        # Django REST Framework API (Python)
│   ├── artifacts/  # Artifact model with auto QR generation
│   ├── web/        # Server-rendered web UI
│   └── ...
├── frontend/       # Flutter app — iOS / Android / Web (PWA)
├── crawler/        # Web crawler for discover-cameroon.com
└── downloads/      # Crawled content & images
```

## Quick Start

### Backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### Import Crawl Data
```bash
cd backend
python manage.py import_crawl_data                         # Import content and images
python manage.py import_crawl_data --dry-run               # Validate without saving
python manage.py import_crawl_data --update-existing       # Refresh existing artifacts and images
```

### Seed Stories, Quizzes, and Badges
Run these after migrations to populate the web app with stories and gamification data:

```bash
cd backend
python manage.py seed_stories                         # Create story categories and stories
python manage.py seed_gamification                    # Create quizzes for every published story
python manage.py seed_gamification --clear            # Rebuild quizzes and badges from scratch
```

`seed_gamification` preserves existing custom quizzes, repairs empty quizzes, and generates a four-question quiz for every published story that does not have custom questions.

### Refresh Existing Media
The seed and import commands also attach downloaded images to existing records:

```bash
cd backend
python manage.py seed_stories
python manage.py import_crawl_data --update-existing
```

After starting the server, stories are available at `/stories/`, quizzes at `/quizzes/`, and artifacts at `/artifacts/`.

### Web Crawler
```bash
python crawler/main.py              # Full crawl + download
python crawler/main.py --dry-run    # Crawl only, no downloads
```

## Roadmap

| Phase | Focus |
| ----- | ----- |
| 1 | Project setup & baseline architecture |
| 2 | Auth, user roles & compliance |
| 3 | Storytelling, repository & reader engine |
| 4 | Media, AI video (Luma AI) & resilient networking |
| 5 | Museum QR code engine & deep linking |
| 6 | Gamification, quizzes & certification |
| 7 | Personalization, library & reading progress |
| 8 | Social sharing & content discovery |
| 9 | Cross-platform PWA & web adaptation |
| 10 | Observability, data seeding & deployment |

See `backend/README.md` for backend setup.
