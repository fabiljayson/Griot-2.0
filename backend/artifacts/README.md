# `artifacts` — RETIRED (migration-history shell)

This app was consolidated into **`qr_codes`** and retired from the runtime
(feature 001, 2026-09-19).

## What lives here (and why)

| Path | Status |
|------|--------|
| `migrations/0001..0003` | **KEPT** — part of the Django migration graph and referenced by `django_migrations` rows in deployed databases. Do **not** delete while any deployed database may reference them. |
| `models.py` | Empty shell. The `Artifact` model was removed in `0003_remove_artifact_model` and consolidated into `qr_codes.Artifact` (narrative fields merged in `qr_codes.0002`). |
| `__init__.py` | Package marker. |

## What was removed

- `views.py`, `urls.py` — duplicate QR landing page. The canonical page is
  `web.artifact_detail_view` at `/artifact/<slug>/`.
- `admin.py`, `apps.py` — empty stubs.
- `management/commands/import_crawl_data.py` — relocated **verbatim** to
  `qr_codes/management/commands/import_crawl_data.py` (same invocation:
  `python manage.py import_crawl_data`).

## Compatibility

Legacy printed QR codes encoding `/artifacts/<slug>/` are handled by a
permanent 301 redirect in `config/urls.py` to `/artifact/<slug>/`.

## Full removal (future milestone)

Deleting `artifacts/` entirely requires a documented migration milestone:

1. Verify no deployed database still applies this app's migrations
   (`django_migrations` bookkeeping) — or plan a coordinated cleanup.
2. Remove the migration files in the same change as the directory.
3. Update the README structure listing.

Until then, this shell must stay exactly as-is.
