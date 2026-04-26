#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${SYNCANTINOTE_API_BASE_URL:-https://feisio.com/feisiomark/api}"
DEVICE_ID="${1:-${SYNCANTINOTE_DEVICE_ID:-}}"
DEVICE_NAME="${2:-${SYNCANTINOTE_DEVICE_NAME:-}}"
ENROLLMENT_KEY="${SYNCANTINOTE_ENROLLMENT_KEY:-}"

if [[ -z "${DEVICE_ID}" || -z "${DEVICE_NAME}" ]]; then
  echo "Usage: SYNCANTINOTE_API_BASE_URL=<url> ./scripts/enroll_device.sh <device_id> <device_name>"
  echo "Or provide SYNCANTINOTE_DEVICE_ID and SYNCANTINOTE_DEVICE_NAME in environment."
  exit 1
fi

tmp_response="$(mktemp)"
trap 'rm -f "${tmp_response}"' EXIT

headers=(-H "Content-Type: application/json")
if [[ -n "${ENROLLMENT_KEY}" ]]; then
  headers+=(-H "x-syncantinote-enrollment-key: ${ENROLLMENT_KEY}")
fi

payload="$(printf '{"device_id":"%s","device_name":"%s"}' "${DEVICE_ID}" "${DEVICE_NAME}")"

http_code="$({
  curl -sS -o "${tmp_response}" -w "%{http_code}" \
    -X POST "${API_BASE_URL}/auth/device" \
    "${headers[@]}" \
    --data "${payload}"
} || true)"

if [[ "${http_code}" != "200" ]]; then
  echo "Enrollment failed with HTTP ${http_code}"
  cat "${tmp_response}"
  exit 1
fi

token="$(node -e '
let body = "";
process.stdin.on("data", (d) => (body += d));
process.stdin.on("end", () => {
  try {
    const parsed = JSON.parse(body);
    if (!parsed.token || typeof parsed.token !== "string") {
      process.exit(2);
      return;
    }
    process.stdout.write(parsed.token);
  } catch {
    process.exit(2);
  }
});
' < "${tmp_response}")"

if [[ -z "${token}" ]]; then
  echo "Enrollment response did not include token"
  cat "${tmp_response}"
  exit 1
fi

echo "${token}"
