# Griot 2.0 — Django Backend

Backend API for the **African Teller** digital heritage platform (Cameroon oral
traditions, museum artifact QR codes, AI-generated video, gamified learning).

## Stack

- Django 5.2 + Django REST Framework
- SQLite (`db.sqlite3`) for local dev
- SimpleJWT (auth — Phase 2), CORS, Pillow, blurhash-python, firebase-admin
  (FCM — Phase 4), sentry-sdk (Phase 10)

## Project structure

```
backend/
├── config/            # Django project package
│   └── settings/      # Split settings: base.py / dev.py / prod.py
├── users/             # Custom user model & roles (Phase 2)
├── stories/           # Story repository & reader engine (Phase 3)
├── qr_codes/          # Artifact QR engine (Phase 5)
├── gamification/      # Quizzes, badges & certificates (Phase 6)
├── api/               # Top-level API routing & health endpoint
├── requirements.txt
└── manage.py
```

## Getting started

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

Health probes: `GET http://127.0.0.1:8000/api/health/` (liveness), `/api/health/ready/` (readiness), `/api/health/metrics/` (metrics)

## Settings split

| Module                  | Purpose                                  |
| ----------------------- | ---------------------------------------- |
| `config.settings.dev`   | Local dev, DEBUG on, CORS wide open      |
| `config.settings.prod`  | Production, DEBUG off, Sentry enabled    |

The default settings module is `config.settings.dev` (see `manage.py`).
Override with the `DJANGO_SETTINGS_MODULE` environment variable.

## Environment variables

Required for production (`config.settings.prod`):

- `DJANGO_SECRET_KEY`
- `DJANGO_ALLOWED_HOSTS`
- `DJANGO_CORS_ORIGINS` (comma-separated allowed web origins)
- `SENTRY_DSN` (optional — enables error monitoring)

## Observability (Phase 10)

### Health probes

| Endpoint                | Purpose                                                              |
| ----------------------- | -------------------------------------------------------------------- |
| `GET /api/health/`      | Liveness — always 200 when the process is up                         |
| `GET /api/health/ready/`| Readiness — checks the DB, returns 200 or 503                       |
| `GET /api/health/metrics/` | Lightweight metrics — uptime, requests served, record counts     |

The metrics endpoint is intentionally unauthenticated (probes/load balancers
need it) and exposes **aggregate counts only** — never individual records or
user data. Process gauges are per-worker; aggregate across replicas with a
real metrics pipeline for production dashboards.

### Structured logging

All loggers emit single-line JSON (`api.logging.JsonFormatter`). Every request
is logged by `api.middleware.RequestLogMiddleware` with method, path, status,
duration, user, and IP. Set `DJANGO_LOG_LEVEL` to override the level
(default `INFO`).

### Error monitoring (Sentry)

Set `SENTRY_DSN` in production to enable Sentry with the Django integration
(`config.settings.prod`). The Flutter client accepts the same via
`--dart-define=SENTRY_DSN=...`.

## Data seeding (Phase 10)

| Command                     | What it seeds                                        |
| --------------------------- | ---------------------------------------------------- |
| `python manage.py seed_all` | Everything below, in one go (add `--clear` to reset) |
| `python manage.py seed_users` | Admin + demo visitor/contributor/manager users      |
| `python manage.py seed_stories` | Story categories & cultural stories                |
| `python manage.py seed_gamification` | Badges & quizzes for published stories         |
| `python manage.py seed_qr_codes` | Museum artifacts for the QR engine                |

Each command is idempotent (`get_or_create`). `--clear` resets the seeded data
before re-seeding: `seed_qr_codes --clear` only removes the artifacts it owns
(by title — user-created artifacts are untouched), while `seed_stories --clear`
clears the story & category tables (existing convention). Demo user password
defaults to `demo12345` — a warning is printed unless `--password` is passed;
use a real secret outside local dev.
