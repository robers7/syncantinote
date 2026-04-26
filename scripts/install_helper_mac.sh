#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install_helper_mac.sh [-p "<Application Support folder>"]

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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="${SYNCANTINOTE_NODE_BIN:-$(command -v node || true)}"
if [[ -z "${NODE_BIN}" ]]; then
  echo "Node.js is required but not found in PATH."
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is required to build the macOS status bar app."
  echo "Install Xcode Command Line Tools and rerun: xcode-select --install"
  exit 1
fi

API_BASE_URL="${SYNCANTINOTE_API_BASE_URL:-https://feisio.com/feisiomark/api}"
DEVICE_NAME="${SYNCANTINOTE_DEVICE_NAME:-$(scutil --get ComputerName 2>/dev/null || hostname)}"
DEVICE_ID_DEFAULT="$(echo "${DEVICE_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
DEVICE_ID="${SYNCANTINOTE_DEVICE_ID:-${DEVICE_ID_DEFAULT}}"
ANTINOTE_DB_PATH="${APP_SUPPORT_DIR}/Antinote/notes.sqlite3"
HELPER_DB_PATH="${APP_SUPPORT_DIR}/AntinoteSync/sync_state.sqlite3"
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
  echo "Install Antinote first, then run the installer again."
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

CONFIG_DIR="${APP_SUPPORT_DIR}/AntinoteSync"
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

swift_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

SWIFT_SOURCE="${CONFIG_DIR}/syncantinote_status_app.swift"
ESC_ENV_FILE="$(swift_escape "${ENV_FILE}")"
ESC_NODE_BIN="$(swift_escape "${NODE_BIN}")"
ESC_HELPER_ENTRY="$(swift_escape "${REPO_ROOT}/apps/helper/dist/index.js")"
ESC_WORKDIR="$(swift_escape "${REPO_ROOT}")"
ESC_LOG_OUT="$(swift_escape "${LOG_DIR}/helper.out.log")"
ESC_LOG_ERR="$(swift_escape "${LOG_DIR}/helper.err.log")"

cat > "${SWIFT_SOURCE}" <<EOF
import AppKit
import Foundation

func loadEnvFile(_ path: String) -> [String: String] {
  guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
    return [:]
  }

  var env: [String: String] = [:]
  for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.hasPrefix("#") {
      continue
    }

    guard let idx = trimmed.firstIndex(of: "=") else {
      continue
    }

    let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
    let value = String(trimmed[trimmed.index(after: idx)...])
    if !key.isEmpty {
      env[key] = value
    }
  }

  return env
}

func appendFileHandle(_ path: String) -> FileHandle? {
  let fm = FileManager.default
  if !fm.fileExists(atPath: path) {
    fm.createFile(atPath: path, contents: nil)
  }

  guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
    return nil
  }
  try? handle.seekToEnd()
  return handle
}

final class StatusAppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var helperProcess: Process?

  private let envFile = "${ESC_ENV_FILE}"
  private let nodeBin = "${ESC_NODE_BIN}"
  private let helperEntry = "${ESC_HELPER_ENTRY}"
  private let workDir = "${ESC_WORKDIR}"
  private let logOut = "${ESC_LOG_OUT}"
  private let logErr = "${ESC_LOG_ERR}"

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    setupStatusItem()
    startHelper()
  }

  func applicationWillTerminate(_ notification: Notification) {
    stopHelper()
  }

  private func setupStatusItem() {
    if let button = statusItem.button {
      if #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Syncantinote")
      } else {
        button.title = "Sync"
      }
      button.toolTip = "Syncantinote helper"
    }

    let menu = NSMenu()
    let closeItem = NSMenuItem(title: "Close", action: #selector(closeClicked), keyEquivalent: "q")
    closeItem.target = self
    menu.addItem(closeItem)
    statusItem.menu = menu
  }

  @objc private func closeClicked() {
    stopHelper()
    NSApp.terminate(nil)
  }

  private func startHelper() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: nodeBin)
    process.arguments = [helperEntry]
    process.currentDirectoryURL = URL(fileURLWithPath: workDir)

    var env = ProcessInfo.processInfo.environment
    for (k, v) in loadEnvFile(envFile) {
      env[k] = v
    }
    process.environment = env

    process.standardOutput = appendFileHandle(logOut)
    process.standardError = appendFileHandle(logErr)

    process.terminationHandler = { _ in
      DispatchQueue.main.async {
        NSApp.terminate(nil)
      }
    }

    do {
      try process.run()
      helperProcess = process
    } catch {
      NSApp.terminate(nil)
    }
  }

  private func stopHelper() {
    guard let process = helperProcess else {
      return
    }

    if process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(2)
      while process.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
      }
      if process.isRunning {
        process.interrupt()
      }
    }

    helperProcess = nil
  }
}

let app = NSApplication.shared
let delegate = StatusAppDelegate()
app.delegate = delegate
app.run()
EOF

swiftc -O -framework AppKit "${SWIFT_SOURCE}" -o "${APP_BIN}"
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

echo "Syncantinote helper installed and running."
echo "Device ID: ${DEVICE_ID}"
echo "Application Support base: ${APP_SUPPORT_DIR}"
echo "App: ${APP_DIR}"
echo "Status bar icon: visible while helper is running (menu option: Close)."
echo "Logs: ${LOG_DIR}/helper.out.log and ${LOG_DIR}/helper.err.log"
