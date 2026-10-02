# Griot 2.0 — Django Backend

Backend API for the **African Teller** digital heritage platform (Cameroon oral
traditions, museum artifact QR codes, AI-generated video, gamified learning).

## Stack

- Django 5.2 + Django REST Framework
- SQLite (`db.sqlite3`) for local dev
- SimpleJWT (auth), CORS, Pillow, qrcode, blurhash-python
- Tailwind CSS (Play CDN for web UI)

## Python version

**3.12.10 is the supported version.** It is what `render.yaml` deploys and what
the backend CI job pins, so a green local run and a green CI run mean the same
thing. 3.14 also works locally and the suite passes on it, but it is not what
production runs — prefer 3.12.10 for anything you intend to deploy.

```bash
python3.12 -m venv .venv-linux
```

## Color Palette

The platform uses a **Cameroonian heritage-inspired** color system:

| Color | Hex | CSS Class | Usage |
|-------|-----|-----------|-------|
| 🟦 | `#1E2B58` | `cam-indigo` | Primary headers, navigation |
| 🟨 | `#C68B29` | `cam-bronze` | CTAs, active states, audio |
| 🟥 | `#A0382B` | `cam-earth` | Historical alerts, badges |
| 🟩 | `#1B4332` | `cam-green` | Success states, location tags |
| ⬜ | `#FBF9F4` | `cam-ivory` | Background canvas |
| ⬜ | `#FFFFFF` | `cam-white` | Cards, surfaces |
| ⬛ | `#1C1C1E` | `cam-dark` | Body text |

## Project structure

```
backend/
├── config/            # Django project package
│   └── settings/      # Split settings: base.py / dev.py / prod.py / test.py
├── users/             # Custom user model & roles
├── stories/           # Story repository & reader engine
├── qr_codes/          # Canonical artifact model, QR engine & import command
├── artifacts/         # RETIRED: migration-history shell only (see artifacts/README.md)
├── gamification/      # Quizzes, badges, certificates & reading streaks
├── notifications/     # Reader inbox: new-story, trending digest, streak nudges
├── media_app/         # Luma AI video & TTS narration jobs
├── api/               # Top-level API routing, health, analytics, seeding
├── web/               # Server-rendered web UI (session auth, mirrors mobile)
├── templates/         # Django templates
│   └── web/           # Web UI templates (incl. artifact detail, mobile-first)
├── static/web/        # Web UI assets
├── media/             # Uploaded files
│   ├── artifacts/     # Artifact images from crawl data
│   └── qr_codes/      # Auto-generated QR code PNGs
├── requirements.txt
└── manage.py
```

## Getting started

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### Testing the app on a USB-connected device

A phone on Wi-Fi cannot always reach this machine (guest/captive-portal
networks, or `ufw` blocking the port). Over the cable it always can — the
traffic goes through `adbd` instead of the network stack, so no firewall rule
or Wi-Fi reachability is involved:

```bash
./scripts/dev_usb_setup.sh
```

Starts Django on `0.0.0.0:8000` if it is not already up, then maps the
phone's `127.0.0.1:8000` onto it with `adb reverse`. The app then talks to the
local SQLite database through that tunnel — build it with:

```bash
cd ../frontend
flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

`adb reverse` does not survive unplugging the cable or rebooting the phone;
re-run the script afterwards. Both steps are idempotent, so it is safe to run
before every test session. Override the port or log with `PORT=9000
LOG=/tmp/g.log ./scripts/dev_usb_setup.sh`.

### Import Crawl Data

Import the 127 crawled artifacts from discover-cameroon.com. The command
lives in the canonical `qr_codes` app:

```bash
python manage.py import_crawl_data              # Full import with images
python manage.py import_crawl_data --dry-run    # Validate only
python manage.py import_crawl_data --update-existing  # Update existing
```

This creates artifacts with:
- Combined story (description + historical significance)
- Category (kingdom, landmark, artifact, legend, culture)
- Location metadata
- Auto-generated QR codes
- Downloaded images from source

## Key Features

### Auto QR Code Generation

When an artifact is created or updated in Django Admin, a QR code PNG is
automatically generated encoding the artifact's detail URL (`/artifact/<slug>/`).

```python
# The QR code is generated automatically on save
artifact = Artifact.objects.create(
    title="Foumban Palace",
    story="The royal palace was built in 1917...",
    category="kingdom",
    location="Foumban, West Region",
)
# artifact.qr_code is now a PNG file at /media/qr_codes/foumban-palace-qr.png
```

### Mobile-First Templates

The artifact detail page (`/artifact/<slug>/`) is optimized for mobile:
- Sticky header with back button
- Audio player for narration
- Responsive video embed (16:9)
- Story section with clean typography
- QR code download for sharing

### Web Crawler Integration

The project includes a web crawler (`crawler/main.py`) that extracts content
from discover-cameroon.com and downloads images. The crawled data can be
imported into the database using the `import_crawl_data` management command.

## Settings split

| Module                  | Purpose                                  |
| ----------------------- | ---------------------------------------- |
| `config.settings.dev`   | Local dev, DEBUG on, CORS wide open      |
| `config.settings.test`  | Test runner: high throttle limits, in-memory DB |
| `config.settings.prod`  | Production, DEBUG off, Sentry enabled    |

## Environment variables

Required for production:

- `DJANGO_SECRET_KEY`
- `DJANGO_ALLOWED_HOSTS`
- `DJANGO_CORS_ORIGINS` (comma-separated)
- `DATABASE_URL` (optional — Postgres; falls back to SQLite)
- `SENTRY_DSN` (optional — error monitoring)
- `SITE_URL` (optional — for QR codes, defaults to `https://africanteller.org`)

## Web interface

The backend serves a **server-rendered web UI** at `/` that mirrors the Flutter
app screens. It uses Django sessions and calls the same models.

Key routes:
- `/` — Home dashboard
- `/stories/` — Story discovery
- `/story/<slug>/` — Story reader
- `/artifacts/` — Artifact catalog
- `/artifact/<slug>/` — Artifact detail (QR landing page)
- `/admin/` — Django admin

### Legacy artifact URLs

The pre-consolidation landing path `/artifacts/<slug>/` (note the plural)
permanently redirects (301) to `/artifact/<slug>/` so printed QR codes
from earlier museum materials keep working. The old `artifacts` app is
retired; only its migration history remains under `artifacts/migrations/`
(see `artifacts/README.md`).

## Data seeding

| Command | Purpose |
|---------|---------|
| `seed_all` | Everything below, in one go |
| `seed_users` | Admin + demo users |
| `seed_stories` | Story categories & cultural stories |
| `seed_gamification` | Badges & quizzes |
| `seed_qr_codes` | Museum artifacts |
| `seed_narrations` | TTS narration audio |
| `import_crawl_data` | Import crawled Cameroon content |
