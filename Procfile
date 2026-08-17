# Griot 2.0 — backend web process (Heroku-style platforms)
#
# Deploys the Django backend from the repo root. Requires these env vars at
# runtime (set in the platform dashboard; Render sets them from render.yaml):
#   DJANGO_SETTINGS_MODULE  -> config.settings.prod (set inline below)
#   DJANGO_SECRET_KEY       -> required; prod.py fails fast if missing
#   DJANGO_ALLOWED_HOSTS    -> comma-separated hosts (Render can use
#                              RENDER_EXTERNAL_HOSTNAME instead)
#   DATABASE_URL            -> Postgres URL (optional; falls back to SQLite)
web: cd backend && DJANGO_SETTINGS_MODULE=config.settings.prod gunicorn config.wsgi:application --workers 2 --bind 0.0.0.0:$PORT
