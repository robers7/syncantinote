# Syncantinote Implementation Plan

## 1. Goals and Scope

Syncantinote provides safe logical-record synchronization for Antinote notes across devices by using:

- A client-side sync helper on each device.
- A server-side API on VPS (`devops@feisio.com`) with canonical sync state.
- Revision-based optimistic concurrency (`base_server_revision` check).

Non-goal for v1:

- No raw SQLite file sync.
- No schema modifications to Antinote DB.
- No live remote writes while Antinote is open.

## 2. Deployment Topology

- Source of truth for code: `https://github.com/robers7/syncantinote`.
- Production host: `devops@feisio.com`.
- Public domains:
  - `https://feisio.com/feisiomark`
  - `https://feisio.co.uk/feisiomark`
- VPS hosts multiple apps already, so deployment is isolated to a dedicated path and service unit.

Recommended VPS paths:

- App root: `/srv/apps/syncantinote`
- Runtime data: `/var/lib/syncantinote`
- Logs: journald (`systemd`) + optional `/var/log/syncantinote`

## 3. High-Level Architecture

```text
Antinote local SQLite (read-only snapshot)
        -> Sync Helper shadow DB (`sync_state.sqlite3`)
        -> HTTPS Sync API on VPS
        -> Canonical server database (SQLite initially)
```

## 4. Data Model

### 4.1 Client helper shadow state

- `note_id`
- `last_seen_hash`
- `last_seen_updated_at`
- `last_synced_server_revision`
- `dirty_status`
- `pending_conflict`

### 4.2 Server tables

- `notes`: latest canonical row state.
- `changes`: append-only revision log for pull-by-revision.
- `devices`: device registration and token hash.

## 5. Sync Protocol

### 5.1 Push

Client sends each change with:

- `note_id`
- `operation` (`upsert` or `delete`)
- `base_server_revision`
- note payload
- `local_updated_at`

Server behavior:

- Accept only if server current revision equals `base_server_revision`.
- On accept: increment revision, update `notes`, append `changes`.
- On mismatch: return conflict entry (`409` semantic for that record).

### 5.2 Pull

Client requests `GET /sync/pull?since_revision=<n>`.

Server returns ordered change entries above revision `n`.

### 5.3 Apply strategy on client

- If Antinote is closed: apply remote changes to local DB.
- If Antinote is open: queue remote apply operations until closed.

## 6. Conflict Policy (v1)

Use Level 1 conflict handling (keep both copies):

- Preserve local edit.
- Create sibling note containing remote version with conflict suffix and timestamp/device marker.

This guarantees no silent data loss.

## 7. Security and Authentication

- Device enrollment endpoint issues token.
- Store only token hash server-side.
- Require `Authorization: Bearer <token>` on sync endpoints.
- TLS terminated by Nginx.
- API bound to localhost port; only Nginx exposes public path.

## 8. API Contract (v1)

- `POST /auth/device`
- `POST /sync/push`
- `GET /sync/pull?since_revision=<n>`
- `POST /sync/ack` (optional in v1, useful for diagnostics)
- `GET /health`

## 9. Delivery Phases

### Phase 0: Foundation

- Initialize monorepo structure.
- Add server/helper skeleton and DB migrations.
- Add deployment scripts + Nginx/systemd templates.

### Phase 1: Read-only upload

- Helper snapshots Antinote DB.
- Detect local changes via shadow DB.
- Push upserts/deletes to server.

Success criteria:

- Notes from one device reliably appear in canonical server DB.

### Phase 2: Controlled pull/apply

- Pull changes since revision.
- Apply only when Antinote closed; queue otherwise.

Success criteria:

- Second device receives and applies remote changes after Antinote closes.

### Phase 3: Full two-way with conflicts

- Revision mismatch conflict responses.
- Keep-both conflict copies.
- Deletion propagation.

Success criteria:

- Concurrent edits never lose data.

### Phase 4: Hardening

- Retry/backoff and idempotency keys.
- Structured logs/metrics.
- Backup/restore scripts for server DB.

## 10. Operations Workflow

After each feature implementation:

1. Commit to local git.
2. Push to GitHub.
3. Run deployment script from dev machine.
4. Script SSHes to VPS, pulls latest, migrates, restarts service, validates health.

## 11. Risks and Mitigations

- Risk: writing into Antinote while open can be overwritten by app memory cache.
- Mitigation: remote apply only when Antinote is closed in v1.

- Risk: VPS hosts many apps.
- Mitigation: dedicated systemd unit, dedicated location block path, no global Nginx changes.

- Risk: unstable note identifiers.
- Mitigation: enforce stable UUID mapping in helper shadow DB.

## 12. Immediate Build Output in This Repo

This repository now includes:

- Initial server scaffold with revision-safe push/pull API shape.
- Initial helper scaffold with external shadow DB and sync loop.
- Deployment scripts for GitHub->VPS pull/restart flow.
- Nginx/systemd templates designed for non-disruptive integration.
