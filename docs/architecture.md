# Syncantinote Architecture

## Components

- `apps/server`: Sync API and canonical database.
- `apps/helper`: Device-side sync helper process.
- `deploy/nginx`: Nginx location config snippets.
- `deploy/systemd`: Service templates for server runtime.
- `scripts`: Deployment automation from dev to VPS.

## Primary principles

- Sync logical note records, never SQLite files.
- Use revision-based optimistic concurrency.
- Keep helper state outside Antinote DB.
- Avoid writes into Antinote DB while Antinote is running.

## Data flow

1. Helper makes read-only snapshot of Antinote DB.
2. Helper compares snapshot note rows to local shadow DB state.
3. Helper pushes local changes with `base_server_revision`.
4. Server accepts/rejects per revision check.
5. Helper pulls remote changes since watermark revision.
6. Helper applies remote changes when Antinote is closed, otherwise queues.

## Revision semantics

For each note update:

- Client includes expected `base_server_revision`.
- Server only accepts if current row revision matches this base revision.
- Accepted update increments revision and logs in `changes` table.

Conflicts are represented as per-note rejection details, never silent overwrite.
