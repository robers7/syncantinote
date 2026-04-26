# Syncantinote

Syncantinote is a two-part synchronization system for Antinote data:

- `apps/server`: canonical sync API hosted on VPS.
- `apps/helper`: client-side sync helper that reads local Antinote SQLite and syncs logical changes.

## Design constraints

- Do not sync raw SQLite files.
- Do not modify Antinote DB schema.
- Use optimistic concurrency with `base_server_revision`.
- Prefer applying remote writes only when Antinote is closed.

## Quick repo layout

- `IMPLEMENTATION_PLAN.md`: full delivery plan.
- `docs/architecture.md`: architecture overview.
- `apps/server`: server API and canonical DB.
- `apps/helper`: local helper process and shadow DB.
- `scripts/deploy.sh`: push and deploy to VPS.
- `deploy/nginx`: Nginx integration snippets.
- `deploy/systemd`: service templates.

## Deployment model

All production deployment is pull-based via GitHub:

1. Commit feature.
2. Push to `origin`.
3. Run `scripts/deploy.sh` from dev machine.
4. Script SSHes to VPS, pulls latest, builds, migrates, restarts service.

## Safety

Nginx and service templates are isolated for `/feisiomark` path to avoid impact on other VPS apps.
