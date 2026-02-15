#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SESSION_NAME="${SESSION_NAME:-privatecodexproxy_share}"

screen_session_exists() {
  command -v screen >/dev/null 2>&1 && screen -list 2>/dev/null | grep -q "[.]${SESSION_NAME}[[:space:]]"
}

echo
echo "========================================"
echo "  ChatGPT Proxy - Stop Background Share"
echo "========================================"
echo

if screen_session_exists; then
  echo "[INFO] Stopping screen session: $SESSION_NAME"
  screen -S "$SESSION_NAME" -X stuff $'\003'
  sleep 2
  if screen_session_exists; then
    screen -S "$SESSION_NAME" -X quit || true
  fi
else
  echo "[INFO] No running screen session found."
fi

bash "$SCRIPT_DIR/5_stop_public_share.sh" || true

echo
echo "[OK] Background share stopped."

