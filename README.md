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

## Stage 1 quickstart (first real Mac)

1. Ensure VPS is deployed and healthy:
  - `https://feisio.com/feisiomark/health`
2. Open the hosted installer page:
  - `https://feisio.com/syncantinote/`
3. Download and run `SyncantinoteInstaller.command`.
4. Enter the enrollment key when prompted.
5. Verify helper logs:
  - `~/Library/Logs/Syncantinote/helper.out.log`
  - `~/Library/Logs/Syncantinote/helper.err.log`

Terminal alternative:

- `curl -fsSL https://feisio.com/syncantinote/install.command -o ~/Downloads/SyncantinoteInstaller.command && chmod +x ~/Downloads/SyncantinoteInstaller.command && ~/Downloads/SyncantinoteInstaller.command`

Optional custom Application Support base folder:

- `~/Downloads/SyncantinoteInstaller.command -p "$HOME/SomeOtherApplicationSupport"`

Manual repository-based fallback:

- optional if configured on server: `export SYNCANTINOTE_ENROLLMENT_KEY="..."`
- run: `./scripts/install_helper_mac.sh`

This bootstrap downloads the helper, performs device enrollment, writes local helper config, installs `Syncantinote.app`, installs a launch agent, and triggers an immediate one-shot sync push.
By default it uses `~/Library/Containers/com.chabomakers.Antinote/Data/Library/Application Support` as the base folder.
