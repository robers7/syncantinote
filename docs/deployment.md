# Deployment Guide

## 1. One-time VPS setup

1. Run bootstrap script from dev machine:
   - `./scripts/bootstrap_vps.sh`
2. Script creates required directories and installs systemd unit:
   - `/srv/apps/syncantinote`
   - `/var/lib/syncantinote`
   - `/etc/syncantinote/server.env`
3. Confirm the unit exists:
   - `sudo systemctl status syncantinote-server.service`

## 2. Nginx integration

Run from dev machine:

- `./scripts/configure_nginx_vps.sh`

This safely:

- installs `deploy/nginx/syncantinote.location.conf` to `/etc/nginx/snippets/`
- inserts include lines into existing TLS server blocks for `feisio.com` and `feisio.co.uk`
- writes editable backups to `/var/backups/nginx-sites-enabled/`
- validates (`nginx -t`) and reloads Nginx

The include is path-scoped to `/feisiomark` so existing apps remain unaffected.

Manual equivalent (if needed) is to include `deploy/nginx/syncantinote.location.conf` in existing server blocks for:

- `feisio.com`
- `feisio.co.uk`

Then test and reload:

- `sudo nginx -t`
- `sudo systemctl reload nginx`

## 3. Routine deployment (after each feature)

From development machine:

1. Commit your feature changes.
2. Push to GitHub.
3. Run `./scripts/deploy.sh`.

Or single command:

- `./scripts/feature_ship.sh "feat: your change"`

This pushes code then SSHes to VPS, pulls latest, builds, restarts service, and runs health check.

## 4. Stage 1 helper enrollment and install (macOS)

After server + nginx are live, run on a real Mac with Antinote installed:

1. Clone/pull this repository.
2. If server enrollment key is enabled on VPS, export it first:
   - `export SYNCANTINOTE_ENROLLMENT_KEY="..."`
3. Install and start helper:
   - `./scripts/install_helper_mac.sh`

What it does:

- builds helper workspace
- enrolls device via `POST /auth/device`
- writes helper config to `~/Library/Application Support/AntinoteSync/helper.env`
- installs LaunchAgent at `~/Library/LaunchAgents/com.feisio.syncantinote.helper.plist`
- runs immediate `--once` sync so first push starts immediately

Manual enrollment token only (without installer):

- `./scripts/enroll_device.sh <device_id> <device_name>`

## 5. Safety checks

- Confirm app endpoint: `https://feisio.com/feisiomark/health`
- Confirm service: `sudo systemctl status syncantinote-server.service`
- Confirm only path-scoped Nginx changes were applied.
