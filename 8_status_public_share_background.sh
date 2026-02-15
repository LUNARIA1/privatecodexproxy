#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SESSION_NAME="${SESSION_NAME:-privatecodexproxy_share}"
LOG_FILE="$SCRIPT_DIR/screen-public-share.log"

screen_session_exists() {
  command -v screen >/dev/null 2>&1 && screen -list 2>/dev/null | grep -q "[.]${SESSION_NAME}[[:space:]]"
}

echo
echo "========================================"
echo "  ChatGPT Proxy - Background Status"
echo "========================================"
echo

if screen_session_exists; then
  echo "[OK] Running in screen session: $SESSION_NAME"
else
  echo "[INFO] Not running in background session."
fi

if [ -f "$SCRIPT_DIR/PUBLIC_LINK.txt" ]; then
  echo
  echo "[INFO] Current public link:"
  cat "$SCRIPT_DIR/PUBLIC_LINK.txt"
fi

if [ -f "$LOG_FILE" ]; then
  echo
  echo "[INFO] Recent logs:"
  tail -n 30 "$LOG_FILE" || true
fi

for f in \
  "$SCRIPT_DIR/public-server.err.log" \
  "$SCRIPT_DIR/public-server.out.log" \
  "$SCRIPT_DIR/public-tunnel.err.log" \
  "$SCRIPT_DIR/public-tunnel.out.log"
do
  if [ -f "$f" ]; then
    echo
    echo "[INFO] $(basename "$f")"
    tail -n 30 "$f" || true
  fi
done
