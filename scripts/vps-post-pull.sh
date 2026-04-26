#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f package.json ]]; then
  echo "Run this script from repo root on VPS."
  exit 1
fi

echo "Ensuring runtime directories are ready..."
sudo mkdir -p /var/lib/syncantinote /etc/syncantinote
sudo chown -R devops:devops /var/lib/syncantinote

echo "Installing dependencies..."
npm ci

echo "Building server workspace..."
npm run --workspace apps/server build

echo "Restarting syncantinote-server service..."
sudo systemctl daemon-reload
sudo systemctl restart syncantinote-server.service
sudo systemctl status syncantinote-server.service --no-pager --lines=20 || true

echo "Running local health check..."
if ! curl --retry 12 --retry-connrefused --retry-delay 1 -fsS "http://127.0.0.1:3177/health" | cat; then
  echo "Health check failed. Recent logs:"
  sudo journalctl -u syncantinote-server.service --no-pager -n 80
  exit 1
fi

echo "VPS post-pull completed."
