#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"
REMOTE_HOST="${REMOTE_HOST:-devops@feisio.com}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/srv/apps/syncantinote}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository."
  exit 1
fi

echo "Pushing ${BRANCH} to origin..."
git push origin "${BRANCH}"

echo "Deploying ${BRANCH} on ${REMOTE_HOST}:${REMOTE_APP_DIR}..."
ssh "${REMOTE_HOST}" "bash -lc 'set -euo pipefail; cd \"${REMOTE_APP_DIR}\"; git fetch origin; git checkout \"${BRANCH}\"; git pull --ff-only origin \"${BRANCH}\"; ./scripts/vps-post-pull.sh'"

echo "Deployment completed."
