#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

ask_key() {
  local value
  value="$(osascript <<'APPLESCRIPT'
set keyValue to text returned of (display dialog "Enter your Syncantinote enrollment key:" default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue")
return keyValue
APPLESCRIPT
)" || true
  printf '%s' "${value}"
}

ENROLLMENT_KEY="$(ask_key)"
if [[ -z "${ENROLLMENT_KEY}" ]]; then
  echo "Enrollment key is required."
  exit 1
fi

INSTALL_ROOT="$HOME/Library/Application Support/SyncantinoteInstaller"
ARCHIVE_PATH="$INSTALL_ROOT/syncantinote-main.tar.gz"
EXTRACTED_ROOT="$INSTALL_ROOT/syncantinote-main"

mkdir -p "$INSTALL_ROOT"
rm -rf "$EXTRACTED_ROOT"

echo "Downloading Syncantinote helper..."
curl -fsSL "https://github.com/robers7/syncantinote/archive/refs/heads/main.tar.gz" -o "$ARCHIVE_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$INSTALL_ROOT"

export SYNCANTINOTE_ENROLLMENT_KEY="$ENROLLMENT_KEY"
"$EXTRACTED_ROOT/scripts/install_helper_mac.sh"

echo "Install complete."
