#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SESSION_NAME="${SESSION_NAME:-privatecodexproxy_share}"
LOG_FILE="$SCRIPT_DIR/screen-public-share.log"

screen_session_exists() {
  screen -list 2>/dev/null | grep -q "[.]${SESSION_NAME}[[:space:]]"
}

ensure_screen() {
  if command -v screen >/dev/null 2>&1; then
    return 0
  fi

  echo "[INFO] 'screen' is not installed."
  if command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] Installing screen (sudo password may be required)..."
    sudo apt-get update
    sudo apt-get install -y screen
    return 0
  fi

  echo "[ERROR] Install screen manually, then run again."
  exit 1
}

ensure_screen

if screen_session_exists; then
  echo "[INFO] Background session is already running: $SESSION_NAME"
  echo "Attach: screen -r $SESSION_NAME"
  exit 0
fi

rm -f "$LOG_FILE"

screen -dmS "$SESSION_NAME" bash -lc "cd \"$SCRIPT_DIR\"; ./4_start_public_share.sh >> \"$LOG_FILE\" 2>&1"

echo
echo "[OK] Started in background screen session: $SESSION_NAME"
echo "Detach-safe: you can close SSH or shut down your local PC."
echo "Attach logs: screen -r $SESSION_NAME"
echo

for i in $(seq 1 60); do
  if [ -f "$SCRIPT_DIR/PUBLIC_LINK.txt" ]; then
    echo "[OK] PUBLIC_LINK.txt created:"
    echo
    cat "$SCRIPT_DIR/PUBLIC_LINK.txt"
    echo
    exit 0
  fi
  sleep 1
done

echo "[WARN] PUBLIC_LINK.txt is not ready yet."
echo "Check recent logs:"
tail -n 40 "$LOG_FILE" 2>/dev/null || true
if screen_session_exists; then
  echo "[INFO] Session is still running. Wait a bit more, then run ./8_백그라운드상태.sh"
else
  echo "[ERROR] Session ended early. Run ./8_백그라운드상태.sh for details."
fi
