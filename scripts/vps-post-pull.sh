#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f package.json ]]; then
  echo "Run this script from repo root on VPS."
  exit 1
fi

echo "Installing dependencies..."
npm ci

echo "Building server workspace..."
npm run --workspace apps/server build

echo "Restarting syncantinote-server service..."
sudo systemctl daemon-reload
sudo systemctl restart syncantinote-server.service
sudo systemctl status syncantinote-server.service --no-pager --lines=20 || true

echo "Running local health check..."
curl -fsS "http://127.0.0.1:3177/health" | cat

echo "VPS post-pull completed."
