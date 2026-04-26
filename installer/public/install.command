#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: SyncantinoteInstaller.command [-p "<Application Support folder>"]

-p  Base folder that contains Antinote and AntinoteSync subfolders.
    Default: ~/Library/Containers/com.chabomakers.Antinote/Data/Library/Application Support
EOF
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

APP_SUPPORT_DIR="$HOME/Library/Containers/com.chabomakers.Antinote/Data/Library/Application Support"
while getopts ":p:h" opt; do
  case "${opt}" in
    p)
      APP_SUPPORT_DIR="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Option -${OPTARG} requires a value."
      usage
      exit 1
      ;;
    ?)
      echo "Unknown option: -${OPTARG}"
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

APP_SUPPORT_DIR="${APP_SUPPORT_DIR%/}"

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

INSTALL_ROOT="${APP_SUPPORT_DIR}/SyncantinoteInstaller"
ARCHIVE_PATH="$INSTALL_ROOT/syncantinote-main.tar.gz"
EXTRACTED_ROOT="$INSTALL_ROOT/syncantinote-main"

mkdir -p "$INSTALL_ROOT"
rm -rf "$EXTRACTED_ROOT"

echo "Downloading Syncantinote helper..."
curl -fsSL "https://github.com/robers7/syncantinote/archive/refs/heads/main.tar.gz" -o "$ARCHIVE_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$INSTALL_ROOT"

export SYNCANTINOTE_ENROLLMENT_KEY="$ENROLLMENT_KEY"
"$EXTRACTED_ROOT/scripts/install_helper_mac.sh" -p "${APP_SUPPORT_DIR}"

echo "Install complete."
