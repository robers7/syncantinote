#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-devops@feisio.com}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/srv/apps/syncantinote}"

ssh "${REMOTE_HOST}" "bash -lc '
  set -euo pipefail
  sudo mkdir -p /srv/apps /var/lib/syncantinote /etc/syncantinote

  if [[ ! -d \"${REMOTE_APP_DIR}/.git\" ]]; then
    git clone git@github.com:robers7/syncantinote.git \"${REMOTE_APP_DIR}\"
  fi

  if [[ ! -f /etc/syncantinote/server.env ]]; then
    SALT=\$(openssl rand -hex 32)
    sudo tee /etc/syncantinote/server.env >/dev/null <<EOF
SYNCANTINOTE_SERVER_PORT=3177
SYNCANTINOTE_SERVER_HOST=127.0.0.1
SYNCANTINOTE_SERVER_DB_PATH=/var/lib/syncantinote/server.sqlite3
SYNCANTINOTE_TOKEN_SALT=\$SALT
EOF
  fi

  sudo cp \"${REMOTE_APP_DIR}/deploy/systemd/syncantinote-server.service\" /etc/systemd/system/syncantinote-server.service
  sudo chown -R devops:devops /var/lib/syncantinote
  sudo systemctl daemon-reload
  sudo systemctl enable syncantinote-server.service
'"

echo "VPS bootstrap completed."
