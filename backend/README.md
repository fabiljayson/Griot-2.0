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

Health probe: `GET http://127.0.0.1:8000/api/health/`

## Settings split

| Module                  | Purpose                                  |
| ----------------------- | ---------------------------------------- |
| `config.settings.dev`   | Local dev, DEBUG on, CORS wide open      |
| `config.settings.prod`  | Production, DEBUG off, Sentry enabled    |

The default settings module is `config.settings.dev` (see `manage.py`).
Override with the `DJANGO_SETTINGS_MODULE` environment variable.

## Environment variables

See `.env.example`. Required for production (`config.settings.prod`):

- `DJANGO_SECRET_KEY`
- `DJANGO_ALLOWED_HOSTS`
