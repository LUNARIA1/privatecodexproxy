#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "========================================"
echo "  ChatGPT Proxy - Initial Setup (Linux)"
echo "========================================"
echo

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] node is not installed."
  echo "Install Node.js LTS first: https://nodejs.org"
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[ERROR] npm is not installed."
  echo "Install Node.js LTS first: https://nodejs.org"
  exit 1
fi

echo "[INFO] Installing npm dependencies..."
npm install
echo "[OK] Setup complete."
echo
echo "Next step: run ./2_auth.sh"

