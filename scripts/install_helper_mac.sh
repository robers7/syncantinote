#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="${SYNCANTINOTE_NODE_BIN:-$(command -v node || true)}"
if [[ -z "${NODE_BIN}" ]]; then
  echo "Node.js is required but not found in PATH."
  exit 1
fi

API_BASE_URL="${SYNCANTINOTE_API_BASE_URL:-https://feisio.com/feisiomark/api}"
DEVICE_NAME="${SYNCANTINOTE_DEVICE_NAME:-$(scutil --get ComputerName 2>/dev/null || hostname)}"
DEVICE_ID_DEFAULT="$(echo "${DEVICE_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
DEVICE_ID="${SYNCANTINOTE_DEVICE_ID:-${DEVICE_ID_DEFAULT}}"
ANTINOTE_DB_PATH="${SYNCANTINOTE_ANTINOTE_DB_PATH:-$HOME/Library/Application Support/Antinote/notes.sqlite3}"
HELPER_DB_PATH="${SYNCANTINOTE_HELPER_DB_PATH:-$HOME/Library/Application Support/AntinoteSync/sync_state.sqlite3}"
POLL_INTERVAL_MS="${SYNCANTINOTE_POLL_INTERVAL_MS:-30000}"
ENROLLMENT_KEY="${SYNCANTINOTE_ENROLLMENT_KEY:-}"

prompt_enrollment_key() {
  osascript <<'APPLESCRIPT'
set keyValue to text returned of (display dialog "Enter your Syncantinote enrollment key:" default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue")
return keyValue
APPLESCRIPT
}

if [[ -z "${ENROLLMENT_KEY}" ]]; then
  ENROLLMENT_KEY="$(prompt_enrollment_key || true)"
fi

if [[ -z "${ENROLLMENT_KEY}" ]]; then
  echo "Enrollment key is required."
  exit 1
fi

if [[ ! -f "${ANTINOTE_DB_PATH}" ]]; then
  echo "Antinote DB not found at: ${ANTINOTE_DB_PATH}"
  echo "Set SYNCANTINOTE_ANTINOTE_DB_PATH and run again."
  exit 1
fi

echo "Building helper workspace..."
cd "${REPO_ROOT}"
npm ci
npm run --workspace apps/helper build

echo "Enrolling device with server..."
export SYNCANTINOTE_API_BASE_URL="${API_BASE_URL}"
export SYNCANTINOTE_DEVICE_ID="${DEVICE_ID}"
export SYNCANTINOTE_DEVICE_NAME="${DEVICE_NAME}"
export SYNCANTINOTE_ENROLLMENT_KEY="${ENROLLMENT_KEY}"
TOKEN="$("${REPO_ROOT}/scripts/enroll_device.sh")"

CONFIG_DIR="$HOME/Library/Application Support/AntinoteSync"
LOG_DIR="$HOME/Library/Logs/Syncantinote"
PLIST_PATH="$HOME/Library/LaunchAgents/com.feisio.syncantinote.helper.plist"
APP_DIR="$HOME/Applications/Syncantinote.app"
APP_CONTENTS_DIR="${APP_DIR}/Contents"
APP_MACOS_DIR="${APP_CONTENTS_DIR}/MacOS"
APP_BIN="${APP_MACOS_DIR}/Syncantinote"
mkdir -p "${CONFIG_DIR}" "${LOG_DIR}" "$HOME/Library/LaunchAgents" "$APP_MACOS_DIR"

ENV_FILE="${CONFIG_DIR}/helper.env"
cat > "${ENV_FILE}" <<EOF
SYNCANTINOTE_DEVICE_ID=${DEVICE_ID}
SYNCANTINOTE_DEVICE_NAME=${DEVICE_NAME}
SYNCANTINOTE_API_BASE_URL=${API_BASE_URL}
SYNCANTINOTE_API_TOKEN=${TOKEN}
SYNCANTINOTE_ANTINOTE_DB_PATH=${ANTINOTE_DB_PATH}
SYNCANTINOTE_HELPER_DB_PATH=${HELPER_DB_PATH}
SYNCANTINOTE_POLL_INTERVAL_MS=${POLL_INTERVAL_MS}
EOF
chmod 600 "${ENV_FILE}"

cat > "${APP_CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleExecutable</key>
    <string>Syncantinote</string>
    <key>CFBundleIdentifier</key>
    <string>com.feisio.syncantinote.app</string>
    <key>CFBundleName</key>
    <string>Syncantinote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
  </dict>
</plist>
EOF

cat > "${APP_BIN}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ -f "$HOME/Library/Application Support/AntinoteSync/helper.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$HOME/Library/Application Support/AntinoteSync/helper.env"
  set +a
fi

exec "${NODE_BIN}" "${REPO_ROOT}/apps/helper/dist/index.js"
EOF
chmod +x "${APP_BIN}"

cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.feisio.syncantinote.helper</string>

    <key>ProgramArguments</key>
    <array>
      <string>${APP_BIN}</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${REPO_ROOT}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/helper.out.log</string>

    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/helper.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>SYNCANTINOTE_DEVICE_ID</key>
      <string>${DEVICE_ID}</string>
      <key>SYNCANTINOTE_DEVICE_NAME</key>
      <string>${DEVICE_NAME}</string>
      <key>SYNCANTINOTE_API_BASE_URL</key>
      <string>${API_BASE_URL}</string>
      <key>SYNCANTINOTE_API_TOKEN</key>
      <string>${TOKEN}</string>
      <key>SYNCANTINOTE_ANTINOTE_DB_PATH</key>
      <string>${ANTINOTE_DB_PATH}</string>
      <key>SYNCANTINOTE_HELPER_DB_PATH</key>
      <string>${HELPER_DB_PATH}</string>
      <key>SYNCANTINOTE_POLL_INTERVAL_MS</key>
      <string>${POLL_INTERVAL_MS}</string>
    </dict>
  </dict>
</plist>
EOF

LABEL="gui/$UID/com.feisio.syncantinote.helper"
launchctl bootout "${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "${PLIST_PATH}"
launchctl enable "${LABEL}"
launchctl kickstart -k "${LABEL}"

echo "Running immediate one-shot sync..."
SYNCANTINOTE_RUN_ONCE=1 \
SYNCANTINOTE_DEVICE_ID="${DEVICE_ID}" \
SYNCANTINOTE_DEVICE_NAME="${DEVICE_NAME}" \
SYNCANTINOTE_API_BASE_URL="${API_BASE_URL}" \
SYNCANTINOTE_API_TOKEN="${TOKEN}" \
SYNCANTINOTE_ANTINOTE_DB_PATH="${ANTINOTE_DB_PATH}" \
SYNCANTINOTE_HELPER_DB_PATH="${HELPER_DB_PATH}" \
SYNCANTINOTE_POLL_INTERVAL_MS="${POLL_INTERVAL_MS}" \
"${NODE_BIN}" "${REPO_ROOT}/apps/helper/dist/index.js" --once

echo "Syncantinote helper installed and running."
echo "Device ID: ${DEVICE_ID}"
echo "App: ${APP_DIR}"
echo "Logs: ${LOG_DIR}/helper.out.log and ${LOG_DIR}/helper.err.log"
