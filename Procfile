# Griot 2.0 — backend web process (Heroku-style platforms)
#
# Deploys the Django backend from the repo root. Requires these env vars at
# runtime (set in the platform dashboard; Render sets them from render.yaml):
#   DJANGO_SETTINGS_MODULE  -> config.settings.prod (set inline below)
#   DJANGO_SECRET_KEY       -> required; prod.py fails fast if missing
#   DJANGO_ALLOWED_HOSTS    -> comma-separated hosts (Render can use
#                              RENDER_EXTERNAL_HOSTNAME instead)
#   DATABASE_URL            -> Postgres URL (optional; falls back to SQLite)
#   REDIS_URL               -> Redis URL (see the note on workers below)
#
# WORKERS: 1, matching render.yaml, and with a reason.
#
# Rate limits and the SimpleJWT refresh-token blacklist are both cache-backed,
# and with no REDIS_URL the cache is a per-process LocMemCache. Every extra
# worker is therefore an extra copy of the counters: --workers 2 silently
# doubles the 5/min auth budget, and a refresh token blacklisted by one worker
# still validates on the other. If you raise the worker count, set REDIS_URL
# in the same deploy — the app logs a warning at boot when it is missing.
#
# --threads is safe to raise, because a single LocMemCache is shared between
# threads in one process.
web: cd backend && DJANGO_SETTINGS_MODULE=config.settings.prod gunicorn config.wsgi:application --workers 1 --threads 4 --timeout 120 --max-requests 400 --max-requests-jitter 100 --bind 0.0.0.0:$PORT
