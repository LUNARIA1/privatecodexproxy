#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "========================================"
echo "  ChatGPT Proxy - Server Start (Linux)"
echo "========================================"
echo
echo "Close this terminal or press Ctrl+C to stop."
echo

read -r -p "Restart every how many minutes? (default 60): " RESTART_MIN
RESTART_MIN="${RESTART_MIN:-60}"

if ! [[ "$RESTART_MIN" =~ ^[0-9]+$ ]] || [ "$RESTART_MIN" -le 0 ]; then
  echo "[ERROR] Please enter a positive number."
  exit 1
fi

WAIT_SEC=$((RESTART_MIN * 60))
PID_FILE="$SCRIPT_DIR/server.pid"

echo
echo "Auto-restart interval: $RESTART_MIN minute(s)"
echo

while true; do
  rm -f "$PID_FILE"

  echo "========================================"
  date +"[%Y-%m-%d %H:%M:%S] Starting server..."
  echo "========================================"

  nohup node server.mjs >"$SCRIPT_DIR/server.out.log" 2>"$SCRIPT_DIR/server.err.log" &
  NODE_PID=$!
  echo "$NODE_PID" >"$PID_FILE"

  echo "Running PID: $NODE_PID"
  echo "Restarting in $RESTART_MIN minute(s)..."
  sleep "$WAIT_SEC"

  echo
  date +"[%Y-%m-%d %H:%M:%S] Restarting server..."
  kill "$NODE_PID" >/dev/null 2>&1 || true
  sleep 0.2
  kill -9 "$NODE_PID" >/dev/null 2>&1 || true
done

