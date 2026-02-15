#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "========================================"
echo "  ChatGPT Proxy - Auth (Linux)"
echo "========================================"
echo
echo "A browser will open. Sign in to your ChatGPT account."
echo

AUTH_LOG="$SCRIPT_DIR/auth_result.log"
rm -f "$AUTH_LOG"

AUTH_ARGS=(--auth-only)
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "[INFO] No desktop session detected. Switching to device auth mode."
  echo "[INFO] Follow the URL/code shown in terminal on your phone or PC browser."
  AUTH_ARGS+=(--device)
fi

set +e
node server.mjs "${AUTH_ARGS[@]}" >"$AUTH_LOG" 2>&1
AUTH_EXIT=$?
set -e

cat "$AUTH_LOG"
echo

if grep -Fq "node server.mjs" "$AUTH_LOG"; then
  echo "[OK] Auth success detected."
  exit 0
fi

if [ "$AUTH_EXIT" -ne 0 ]; then
  echo "[ERROR] Auth failed. Please try again."
else
  echo "[INFO] Auth command finished. Check logs above."
fi

exit "$AUTH_EXIT"
