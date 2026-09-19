# Feature Specification: Retire Deprecated Artifacts App & Scope Dev Hosts

**Feature Branch**: `001-retire-artifacts-app`

**Created**: 2026-09-19

**Status**: Draft

**Input**: User description: "Create follow-up tasks from the audit findings (retire the artifacts app, scope dev ALLOWED_HOSTS)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visitor Scans a QR Code and Lands on the Working Detail Page (Priority: P1)

A museum visitor scans an artifact's QR code and arrives at the artifact
detail page. The page they reach MUST be the canonical, feature-complete
artifact detail experience (story, audio guide, related stories, scan
analytics). The retired legacy route MUST NOT serve a duplicate,
feature-poor landing page that silently competes with the canonical one.

**Why this priority**: Printed QR codes in museums encode a URL — if the
landing route regresses, physical visitor engagement breaks with no
in-app recovery path. This is the revenue-relevant, externally visible
surface.

**Independent Test**: Can be fully tested by requesting the canonical
artifact detail URL for a published artifact and confirming content,
plus confirming the legacy route no longer resolves to a page.

**Acceptance Scenarios**:

1. **Given** a published artifact, **When** a visitor requests its
   canonical detail URL (`/artifact/<slug>/`), **Then** they see the
   full detail page (story, audio, related stories).
2. **Given** the same published artifact, **When** any visitor requests
   the legacy URL form (`/artifacts/<slug>/`), **Then** the system
   responds with a permanent redirect to the canonical URL — preserving
   any QR codes printed with the legacy path.
3. **Given** an unpublished or unknown artifact slug, **When** a visitor
   requests either URL form, **Then** they receive a not-found response.

---

### User Story 2 - Developer Runs the Dev Server Without an Over-Broad Host Allow-List (Priority: P2)

A developer runs the local development server. The development
configuration MUST NOT accept requests for arbitrary hostnames; it MUST
be scoped to legitimate development hosts (localhost, 127.0.0.1, and
tunneling hosts used by the team). A misconfigured production-style
request MUST NOT be silently served by a dev server.

**Why this priority**: Defense-in-depth hardening — no direct user
impact today, but eliminates a whole class of host-header confusion
(dns-rebinding-style) risks in development and test environments.

**Independent Test**: Can be fully tested by making requests with a
disallowed Host header against a dev-configured instance and asserting
rejection, and by making requests with allowed hosts and asserting
success.

**Acceptance Scenarios**:

1. **Given** the development settings, **When** a request arrives with
   `Host: localhost`, `Host: 127.0.0.1`, or a team tunneling domain
   (e.g. `*.ngrok-free.app`), **Then** the request is served normally.
2. **Given** the development settings, **When** a request arrives with
   an unrelated host (e.g. `evil.example.com`), **Then** the request is
   rejected with a bad-request response rather than served.
3. **Given** the production settings, **When** the host allow-list is
   evaluated, **Then** it contains only hosts from environment
   configuration (no wildcards, no tunneling defaults).

---

### User Story 3 - Maintainer Understands Where Artifact Code Lives (Priority: P3)

A new maintainer reads the project documentation and the codebase layout.
Documentation MUST describe exactly one canonical location for artifact
logic and the QR landing experience, and the retired app MUST no longer
appear in the app listing — eliminating ambiguity about where changes
belong.

**Why this priority**: Documentation hygiene that prevents future
contributors from reviving the duplicate surface; no runtime behavior.

**Independent Test**: Can be tested by reading the project README and
configuration and confirming the retired app is absent from the
documented app structure and its documented command still exists under
the canonical app.

**Acceptance Scenarios**:

1. **Given** the current documentation, **When** a maintainer reads the
   project structure section, **Then** the retired app is removed from
   the app listing and the import command is documented under the
   canonical artifact app.
2. **Given** the application registry, **When** the system boots, **Then**
   the retired app is no longer registered, and all previously public
   capabilities (artifact landing, import command) remain available from
   the canonical app.

---

### Edge Cases

- What happens when a QR code printed with the legacy `/artifacts/<slug>/`
  URL is scanned after retirement? → Must 301-redirect to
  `/artifact/<slug>/` (permanent redirect preserves SEO and caching).
- What happens when the import command is invoked after the app move?
  → Must work identically under its documented name
  (`python manage.py import_crawl_data`), now owned by the canonical app.
- How does the system handle a request with an IP-address literal host
  (e.g. `Host: 192.168.1.50`) in dev? → Out of scope for allow-listing;
  team uses localhost or tunnels; document as assumption.
- What happens to migrations belonging to the retired app once removed
  from the registry? → Historical migrations MUST remain in place (the
  migration graph references them); only the runtime app registration
  and routing are retired. Migration files MUST NOT be deleted while
  any deployed database may still reference the app.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST serve the canonical artifact detail page at
  the canonical URL (`/artifact/<slug>/`) with full functionality
  (story, audio guide, related stories, scan recording).
- **FR-002**: The system MUST respond to requests for the legacy artifact
  landing URL (`/artifacts/<slug>/`) with a permanent (301) redirect to
  the canonical URL, preserving printed QR code compatibility.
- **FR-003**: The system MUST unregister the deprecated app from the
  application registry so its models module and admin no longer load.
- **FR-004**: The data-import command MUST remain invocable by its
  documented name (`python manage.py import_crawl_data`) after being
  relocated to the canonical app.
- **FR-005**: Development settings MUST allow-list only development
  hosts: localhost, 127.0.0.1, and the team's tunneling domains; the
  blanket wildcard MUST be removed.
- **FR-006**: Production settings MUST NOT be affected: the production
  host allow-list continues to be sourced exclusively from environment
  configuration.
- **FR-007**: Project documentation MUST be updated to remove references
  to the retired app in the structure listing and to reflect the
  canonical owner of the import command.
- **FR-008**: Historical migrations of the retired app MUST be preserved
  on disk until a documented data migration retires them (no destructive
  migration-file cleanup in this feature).
- **FR-009**: All existing automated tests MUST continue to pass after
  the retirement, and new tests MUST cover the legacy-URL redirect
  behavior and the dev host allow-list behavior.

### Key Entities *(include if feature involves data)*

- **Artifact**: Already canonical in the QR-codes app; no schema changes
  in this feature. Attributes relevant here: slug (stable identifier
  used in URLs and QR codes), published flag.
- **QR Code**: Printed/encoded asset referencing a deep-link URL; MUST
  continue resolving after the legacy route is redirected.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A visitor scanning a legacy printed QR code lands on the
  canonical artifact page with exactly one redirect hop, completing in
  under 2 seconds on a standard connection.
- **SC-002**: Zero duplicate artifact landing pages remain: exactly one
  route serves artifact detail content.
- **SC-003**: The development host allow-list contains 3 host patterns
  (localhost, loopback IP, tunneling wildcard) and rejects all others.
- **SC-004**: The full automated test suite passes with the deprecated
  app unregistered, with at least 3 new tests covering redirect, host
  allow-list, and command relocation behavior.
- **SC-005**: A maintainer can locate the import command documentation
  in under 1 minute via the README (single canonical reference, no
  mentions of the retired app path).

## Assumptions

- Printed QR codes and deep links encode `/artifact/<slug>/` today (the
  canonical web route); the legacy `/artifacts/<slug>/` path exists only
  from the pre-consolidation era and from older printed materials.
- Existing installed databases may still contain rows in the retired
  app's historical migration records; therefore migration files stay.
- The team's tunneling provider is ngrok (`.ngrok-free.app`,
  `.ngrok.io`); other tunneling providers would be a follow-up change.
- The web UI's artifact catalog, detail, and audio-generation flows are
  unaffected and remain the canonical surfaces.
- Removing the app from the registry does not require data migration
  because its models were already removed in migration `0003` — the
  database has no legacy tables (beyond the migration bookkeeping row).
