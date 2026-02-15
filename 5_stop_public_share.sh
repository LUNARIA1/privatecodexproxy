#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "========================================"
echo "  ChatGPT Proxy - Stop Public Share"
echo "========================================"
echo

stop_by_pid_file() {
  local file="$1"
  if [ -f "$file" ]; then
    local pid
    pid="$(cat "$file" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.2
      kill -9 "$pid" >/dev/null 2>&1 || true
      echo "Stopped PID $pid from $(basename "$file")"
    fi
    rm -f "$file"
  fi
}

stop_by_pid_file "$SCRIPT_DIR/public-tunnel.pid"
stop_by_pid_file "$SCRIPT_DIR/public-server.pid"

echo "Done."

