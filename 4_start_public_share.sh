#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "========================================"
echo "  ChatGPT Proxy - Public Share (Linux)"
echo "========================================"
echo
echo "This starts:"
echo "  1) local proxy server (port 7860)"
echo "  2) free Cloudflare quick tunnel"
echo
echo "Keep this terminal open while sharing."
echo

set +e
bash "$SCRIPT_DIR/start-public-tunnel.sh"
EXIT_CODE=$?
set -e

echo
if [ "$EXIT_CODE" -ne 0 ]; then
  echo "[ERROR] Public share stopped with error. Code=$EXIT_CODE"
  echo
  echo "[DEBUG] Recent logs:"
  for f in \
    "$SCRIPT_DIR/public-server.err.log" \
    "$SCRIPT_DIR/public-server.out.log" \
    "$SCRIPT_DIR/public-tunnel.err.log" \
    "$SCRIPT_DIR/public-tunnel.out.log"
  do
    if [ -f "$f" ]; then
      echo "----- $(basename "$f") -----"
      tail -n 40 "$f" || true
      echo
    fi
  done
else
  echo "[OK] Public share stopped."
fi

exit "$EXIT_CODE"
