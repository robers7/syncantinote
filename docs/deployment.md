# Deployment Guide

## 1. One-time VPS setup

1. Create app directories:
   - `/srv/apps/syncantinote`
   - `/var/lib/syncantinote`
   - `/etc/syncantinote`
2. Clone repository into `/srv/apps/syncantinote`.
3. Create `/etc/syncantinote/server.env` based on `.env.example` server vars.
4. Copy `deploy/systemd/syncantinote-server.service` to `/etc/systemd/system/`.
5. Reload and enable service:
   - `sudo systemctl daemon-reload`
   - `sudo systemctl enable --now syncantinote-server.service`

## 2. Nginx integration

Include `deploy/nginx/syncantinote.location.conf` in existing server blocks for:

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

## 4. Safety checks

- Confirm app endpoint: `https://feisio.com/feisiomark/health`
- Confirm service: `sudo systemctl status syncantinote-server.service`
- Confirm only path-scoped Nginx changes were applied.
