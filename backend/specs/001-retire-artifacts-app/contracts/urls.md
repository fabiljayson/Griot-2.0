# Contracts: URL & Command Interface

**Feature**: 001-retire-artifacts-app | **Date**: 2026-09-19

This feature introduces no API contract changes. The contracts below fix
the *existing* external interfaces that must not regress, plus the one
new redirect behavior.

## C1: Legacy URL redirect (NEW behavior)

```text
GET /artifacts/{slug}/
  → 301 Moved Permanently
  → Location: /artifact/{slug}/
  → Applies to all slugs (published or not — resolution of the target
    happens on the canonical route; redirect is slug-agnostic)
```

| Property | Value |
|---|---|
| Method | GET (HEAD follows) |
| Auth | None required |
| Status | 301 (permanent) |
| Follow-up request | Canonical route's own semantics (200 for published artifacts, 404 otherwise) |
| Post-redirect scans recorded | Yes — canonical view records QRCodeScan (legacy view never did) |

## C2: Canonical artifact detail (PRESERVED — must not regress)

```text
GET /artifact/{slug}/
  → 200 text/html for published artifacts (full detail page:
    story, audio guide, related stories)
  → 404 for unpublished/unknown slugs
  → Records a QRCodeScan row per request (device=Web)
```

## C3: Artifact API (PRESERVED — must not regress)

```text
GET    /api/artifacts/            → list published artifacts
GET    /api/artifacts/{slug}/     → artifact detail (JSON)
POST   /api/qr/{slug}/scan/       → record scan
GET    /api/artifacts/lookup/?path=/artifact/{slug} → deep-link lookup
```

Mobile client contract — untouched by this feature.

## C4: Management command interface (PRESERVED — owner moves)

```text
python manage.py import_crawl_data            # full import with images
python manage.py import_crawl_data --dry-run  # validate only, no writes
python manage.py import_crawl_data --update-existing  # update existing rows
```

| Property | Before | After |
|---|---|---|
| Invocable by this name | Yes (from `artifacts` app) | Yes (from `qr_codes` app) |
| Behavior | Idempotent import | Identical (verbatim move) |
| Flags | `--dry-run`, `--update-existing` | Identical |
| Discovers via | `artifacts/management/commands/` | `qr_codes/management/commands/` |

## C5: Dev server host contract (TIGHTENED)

```text
Request Host header evaluation (config.settings.dev):
  localhost, 127.0.0.1, *.ngrok-free.app, *.ngrok.io  → served
  anything else                                        → 400 Bad Request

Request Host header evaluation (config.settings.test):
  testserver, localhost, 127.0.0.1                     → served (test client)
  anything else                                        → 400 Bad Request

config.settings.prod: unchanged (env-sourced DJANGO_ALLOWED_HOSTS,
fail-fast when missing).
```
