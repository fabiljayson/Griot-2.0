# Data Model: Retire Deprecated Artifacts App & Scope Dev Hosts

**Feature**: 001-retire-artifacts-app | **Date**: 2026-09-19

## Overview

**This feature makes zero schema changes.** The data model is documented
here only to record what is *touched* (read-only) versus what stays
untouched, and to trace the entities named in the spec.

## Entities (read-only in this feature)

### Artifact (canonical: `qr_codes.models.Artifact`)

| Aspect | Value |
|---|---|
| Touched by this feature | No (read for redirect target resolution only) |
| Relevant fields | `slug` (unique, stable — used in URLs/QR codes), `is_published` |
| Invariants | Slug stability MUST be preserved (Constitution IV) — no slug regeneration |

### Legacy artifacts.Artifact (historical only)

| Aspect | Value |
|---|---|
| Status | Model deleted since migration `0003_remove_artifact_model` |
| Remaining trace | `artifacts/migrations/0001..0003` on disk + `django_migrations` bookkeeping rows in deployed databases |
| Action | None — migration files preserved (FR-008); bookkeeping rows are harmless history |

### QRCodeScan

| Aspect | Value |
|---|---|
| Touched | No |
| Note | Canonical landing view (`web.artifact_detail_view`) already records scans; the removed legacy view never did — removal closes an analytics gap (scans from legacy URLs were previously *not* recorded by the legacy page; after redirect they land on the canonical view and ARE recorded) |

## Settings state model (the only "state" this feature changes)

```text
ALLOWED_HOSTS lifecycle:
  dev.py:  ['localhost', '127.0.0.1', '.ngrok-free.app', '.ngrok.io', '*']
    → ['localhost', '127.0.0.1', '.ngrok-free.app', '.ngrok.io']
  test.py: (inherits base: [] until this feature)
    → adds ['testserver', 'localhost', '127.0.0.1']  (test client requires 'testserver')
  prod.py: env-sourced, unchanged (fail-fast if empty)
  base.py: stays env-driven ([] default) — unchanged

INSTALLED_APPS lifecycle:
  LOCAL_APPS: [... 'web', 'artifacts'] → [... 'web']  (in base.py)
```

## Migration graph (untouched)

```text
artifacts.0001_initial
artifacts.0002_artifact_category_...
artifacts.0003_remove_artifact_model   ← terminal node; file preserved
qr_codes.0001_initial
qr_codes.0002_artifact_add_narrative_fields
...
```

No new nodes; no edges changed; no files deleted.

## URL state transitions

| URL | Before | After |
|---|---|---|
| `/artifact/<slug>/` | canonical detail (web app) | unchanged |
| `/artifacts/<slug>/` | legacy duplicate landing page | **301 → `/artifact/<slug>/`** |
| `/api/artifacts/...` | DRF ViewSet (qr_codes) | unchanged |
| `/api/qr/<slug>/` | scan redirect endpoint (qr_codes) | unchanged |
