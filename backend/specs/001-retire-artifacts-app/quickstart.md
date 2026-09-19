# Quickstart: Retire Deprecated Artifacts App & Scope Dev Hosts

**Feature**: 001-retire-artifacts-app | **Date**: 2026-09-19

End-to-end validation that the retirement works and nothing regressed.

## Prerequisites

- Python venv at `.venv-linux` (Python 3.14) with `requirements.txt` installed
- Migrated database (`python manage.py migrate`) — any state works; the
  legacy artifacts table may or may not exist (bookkeeping-only now)

## 1. Automated checks (the quality gate)

```bash
DJANGO_SETTINGS_MODULE=config.settings.dev .venv-linux/bin/python manage.py check
# Expected: "System check identified no issues (0 silenced)."

.venv-linux/bin/python manage.py makemigrations --check --dry-run
# Expected: "No changes detected"

DJANGO_SETTINGS_MODULE=config.settings.test .venv-linux/bin/python manage.py test
# Expected: "OK" — 141+ tests pass (141 existing + new ones), 0 failures
```

## 2. Command relocation (C4)

```bash
.venv-linux/bin/python manage.py import_crawl_data --dry-run
# Expected: command is FOUND (relocated to qr_codes) and runs validation.
# Any data-validation output is fine; "Unknown command" is a FAILURE.
```

## 3. Legacy URL redirect (C1)

```bash
.venv-linux/bin/python manage.py shell -c "
from django.test import Client
c = Client()
r = c.get('/artifacts/some-slug/')
print(r.status_code, r.headers.get('Location'))
"
# Expected: 301 /artifact/some-slug/
```

## 4. Canonical page intact (C2)

```bash
.venv-linux/bin/python manage.py shell -c "
import django; django.setup()
from qr_codes.models import Artifact
from django.test import Client
a, _ = Artifact.objects.get_or_create(
    slug='quickstart-check', defaults={
        'title': 'Quickstart Check', 'description': 'temp',
        'is_published': True,
    })
r = Client().get('/artifact/quickstart-check/')
print(r.status_code)
a.delete()
"
# Expected: 200
```

## 5. Host scoping (C5)

```bash
DJANGO_SETTINGS_MODULE=config.settings.dev .venv-linux/bin/python -c "
import django; django.setup()
from django.conf import settings
assert '*' not in settings.ALLOWED_HOSTS, 'wildcard still present!'
print('dev hosts:', settings.ALLOWED_HOSTS)
"
# Expected: ['localhost', '127.0.0.1', '.ngrok-free.app', '.ngrok.io']

DJANGO_SETTINGS_MODULE=config.settings.test .venv-linux/bin/python -c "
import django; django.setup()
from django.conf import settings
assert 'testserver' in settings.ALLOWED_HOSTS
print('test hosts:', settings.ALLOWED_HOSTS)
"
# Expected: includes testserver (test client requirement)
```

## 6. App retired (FR-003)

```bash
DJANGO_SETTINGS_MODULE=config.settings.dev .venv-linux/bin/python -c "
import django; django.setup()
from django.conf import settings
assert 'artifacts' not in settings.INSTALLED_APPS
import os
print('registered:', 'artifacts' in settings.INSTALLED_APPS)
print('migrations kept:', os.path.isdir('artifacts/migrations'))
"
# Expected: registered: False / migrations kept: True
```

## Success summary

All five sections pass → SC-001..SC-005 verified: single redirect hop,
one canonical landing surface, scoped host lists, green suite with new
coverage, and single-source command documentation.
