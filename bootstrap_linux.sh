#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/LUNARIA1/privatecodexproxy.git}"
TARGET_DIR="${2:-privatecodexproxy}"
BRANCH="${3:-linuxver}"

echo "[INFO] Repo: $REPO_URL"
echo "[INFO] Directory: $TARGET_DIR"
echo "[INFO] Branch: $BRANCH"

if ! command -v git >/dev/null 2>&1; then
  echo "[ERROR] git is not installed."
  echo "Ubuntu/Debian: sudo apt update && sudo apt install -y git"
  exit 1
fi

if [ ! -d "$TARGET_DIR/.git" ]; then
  git clone -b "$BRANCH" "$REPO_URL" "$TARGET_DIR"
else
  echo "[INFO] Existing repo found. Pulling latest..."
  git -C "$TARGET_DIR" fetch origin "$BRANCH"
  git -C "$TARGET_DIR" checkout "$BRANCH"
  git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
fi

cd "$TARGET_DIR"

chmod +x ./*.sh || true

echo
echo "[OK] Download complete."
echo "Run the same sequence as Windows:"
echo "  1) ./1_install.sh"
echo "  2) ./2_auth.sh"
echo "  3) ./4_start_public_share.sh"
