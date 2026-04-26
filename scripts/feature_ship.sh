#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: ./scripts/feature_ship.sh \"feat: message\" [branch]"
  exit 1
fi

MESSAGE="$1"
BRANCH="${2:-main}"

git add -A

if git diff --cached --quiet; then
  echo "No staged changes to commit."
  exit 0
fi

git commit -m "${MESSAGE}"
./scripts/deploy.sh "${BRANCH}"
