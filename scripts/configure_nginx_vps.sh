#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-devops@feisio.com}"
SNIPPET_SRC="deploy/nginx/syncantinote.location.conf"
SNIPPET_DST="/etc/nginx/snippets/syncantinote.location.conf"

if [[ ! -f "${SNIPPET_SRC}" ]]; then
  echo "Missing ${SNIPPET_SRC}"
  exit 1
fi

scp "${SNIPPET_SRC}" "${REMOTE_HOST}:/tmp/syncantinote.location.conf"

ssh "${REMOTE_HOST}" "bash -lc '
  set -euo pipefail
  TS=\$(date +%Y%m%d%H%M%S)
  BACKUP_DIR=/var/backups/nginx-sites-enabled

  sudo install -m 0644 /tmp/syncantinote.location.conf ${SNIPPET_DST}
  sudo mkdir -p \"\${BACKUP_DIR}\"

  for f in /etc/nginx/sites-enabled/feisio.com /etc/nginx/sites-enabled/feisio.co.uk; do
    if ! sudo grep -q \"include /etc/nginx/snippets/syncantinote.location.conf;\" \"\$f\"; then
      sudo cp \"\$f\" \"\${BACKUP_DIR}/\$(basename \"\$f\").bak-\${TS}\"
      sudo sed -i \"/include snippets\\/claimcraft.conf;/a \\    include /etc/nginx/snippets/syncantinote.location.conf;\" \"\$f\"
    fi
  done

  sudo nginx -t
  sudo systemctl reload nginx
'"

echo "Nginx configuration updated and reloaded on ${REMOTE_HOST}."
