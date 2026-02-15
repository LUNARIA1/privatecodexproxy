#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SERVER_PID_FILE="$SCRIPT_DIR/public-server.pid"
TUNNEL_PID_FILE="$SCRIPT_DIR/public-tunnel.pid"
SERVER_OUT_LOG="$SCRIPT_DIR/public-server.out.log"
SERVER_ERR_LOG="$SCRIPT_DIR/public-server.err.log"
TUNNEL_OUT_LOG="$SCRIPT_DIR/public-tunnel.out.log"
TUNNEL_ERR_LOG="$SCRIPT_DIR/public-tunnel.err.log"
SHARE_NOTE_FILE="$SCRIPT_DIR/PUBLIC_LINK.txt"

STARTED_SERVER=0
SERVER_PID=""
TUNNEL_PID=""
API_KEY=""

print_debug_logs() {
  for f in \
    "$SERVER_ERR_LOG" \
    "$SERVER_OUT_LOG" \
    "$TUNNEL_ERR_LOG" \
    "$TUNNEL_OUT_LOG"
  do
    if [ -f "$f" ]; then
      echo "----- $(basename "$f") -----" >&2
      tail -n 80 "$f" >&2 || true
      echo >&2
    fi
  done
}

on_error() {
  local line="$1"
  local cmd="$2"
  local code="${3:-1}"
  echo "[ERROR] start-public-tunnel.sh failed at line $line (exit=$code)" >&2
  echo "[ERROR] Command: $cmd" >&2
  print_debug_logs
  exit "$code"
}

remove_if_exists() {
  local file="$1"
  [ -f "$file" ] && rm -f "$file"
}

is_pid_running() {
  local pid="$1"
  kill -0 "$pid" >/dev/null 2>&1
}

stop_tracked_process() {
  local pid_file="$1"
  if [ -f "$pid_file" ]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && is_pid_running "$pid"; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.2
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$pid_file"
  fi
}

ensure_command() {
  local name="$1"
  local hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "[ERROR] $name not found. $hint" >&2
    exit 1
  fi
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
    return $?
  fi
  return 1
}

wait_local_server_with_key() {
  local api_key="$1"
  local i
  for i in $(seq 1 40); do
    if curl -fsS "http://localhost:7860/status" -H "Authorization: Bearer $api_key" >/tmp/proxy_status.json 2>/dev/null; then
      if node -e "const fs=require('fs');const s=JSON.parse(fs.readFileSync('/tmp/proxy_status.json','utf8'));process.exit(s?0:1)"; then
        rm -f /tmp/proxy_status.json
        return 0
      fi
    fi
    sleep 0.5
  done
  rm -f /tmp/proxy_status.json
  return 1
}

wait_local_server_no_auth() {
  local i
  for i in $(seq 1 30); do
    if curl -fsS "http://localhost:7860/status" >/tmp/proxy_status.json 2>/dev/null; then
      rm -f /tmp/proxy_status.json
      return 0
    fi
    sleep 0.5
  done
  rm -f /tmp/proxy_status.json
  return 1
}

wait_trycloudflare_url() {
  local i
  for i in $(seq 1 80); do
    local combined
    combined="$(cat "$TUNNEL_OUT_LOG" "$TUNNEL_ERR_LOG" 2>/dev/null || true)"
    local url
    url="$(printf '%s' "$combined" | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com/?' | head -n 1 || true)"
    if [ -n "$url" ]; then
      echo "${url%/}"
      return 0
    fi
    if [ $((i % 2)) -eq 0 ]; then
      echo "[INFO] Waiting for trycloudflare URL..."
    fi
    sleep 0.5
  done
  return 1
}

wait_public_check() {
  local base_url="$1"
  local api_key="$2"
  local i
  for i in $(seq 1 30); do
    if curl -fsS "$base_url/status" -H "Authorization: Bearer $api_key" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

resolve_cloudflared_path() {
  local local_bin="$SCRIPT_DIR/cloudflared"
  if [ -x "$local_bin" ]; then
    echo "$local_bin"
    return 0
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    command -v cloudflared
    return 0
  fi

  ensure_command curl "Install curl and try again."

  echo "[SETUP] cloudflared not found. Downloading local binary..."
  local arch
  arch="$(uname -m)"
  local url=""
  case "$arch" in
    x86_64|amd64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
    aarch64|arm64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
    *) echo "[ERROR] Unsupported architecture for auto-download: $arch" >&2; exit 1 ;;
  esac

  curl -fL "$url" -o "$local_bin"
  chmod +x "$local_bin"
  echo "$local_bin"
}

cleanup_on_exit() {
  stop_tracked_process "$TUNNEL_PID_FILE"
  if [ "$STARTED_SERVER" -eq 1 ]; then
    stop_tracked_process "$SERVER_PID_FILE"
  fi
}

trap cleanup_on_exit EXIT INT TERM
trap 'on_error "$LINENO" "$BASH_COMMAND" "$?"' ERR

echo
echo "========================================"
echo "  ChatGPT Proxy - Public Share Start"
echo "========================================"
echo

ensure_command node "Install Node.js LTS from https://nodejs.org"
ensure_command curl "Install curl and try again."

CLOUDFLARED_PATH="$(resolve_cloudflared_path)"

remove_if_exists "$TUNNEL_OUT_LOG"
remove_if_exists "$TUNNEL_ERR_LOG"
remove_if_exists "$SERVER_OUT_LOG"
remove_if_exists "$SERVER_ERR_LOG"
remove_if_exists "$SHARE_NOTE_FILE"
stop_tracked_process "$TUNNEL_PID_FILE"

if port_in_use 7860; then
  echo "[INFO] Port 7860 already in use. Reusing existing local server."
  API_KEY="dummy"
  if ! wait_local_server_no_auth; then
    echo "[ERROR] Existing server on 7860 is not responding at /status."
    exit 1
  fi
else
  stop_tracked_process "$SERVER_PID_FILE"
  API_KEY="share-$(cat /proc/sys/kernel/random/uuid | tr -d '-')"

  echo "[INFO] One-time API key generated."
  (
    export PROXY_API_KEY="$API_KEY"
    nohup node server.mjs >"$SERVER_OUT_LOG" 2>"$SERVER_ERR_LOG" &
    echo $! >"$SERVER_PID_FILE"
  )

  SERVER_PID="$(cat "$SERVER_PID_FILE")"
  echo "[INFO] Local proxy started. PID=$SERVER_PID"

  if wait_local_server_with_key "$API_KEY"; then
    if ! curl -fsS "http://localhost:7860/status" -H "Authorization: Bearer $API_KEY" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const s=JSON.parse(d);process.exit(s.authenticated?0:1)});"; then
      echo "[ERROR] Not authenticated yet. Run ./2_auth.sh first."
      exit 1
    fi
    STARTED_SERVER=1
  else
    if grep -Fq "EADDRINUSE" "$SERVER_ERR_LOG" 2>/dev/null; then
      echo "[WARN] Port 7860 already in use. Switching to existing server mode."
      stop_tracked_process "$SERVER_PID_FILE"
      API_KEY="dummy"
      if ! wait_local_server_no_auth; then
        echo "[ERROR] Existing server on 7860 is not responding at /status."
        exit 1
      fi
    else
      echo "[ERROR] Local proxy did not become ready on port 7860."
      exit 1
    fi
  fi
fi

echo "[INFO] Local proxy health check passed."

nohup "$CLOUDFLARED_PATH" tunnel --url http://localhost:7860 --no-autoupdate >"$TUNNEL_OUT_LOG" 2>"$TUNNEL_ERR_LOG" &
TUNNEL_PID=$!
echo "$TUNNEL_PID" >"$TUNNEL_PID_FILE"
echo "[INFO] cloudflared started. PID=$TUNNEL_PID"

PUBLIC_BASE="$(wait_trycloudflare_url || true)"
if [ -z "$PUBLIC_BASE" ]; then
  echo "[ERROR] Failed to obtain trycloudflare URL."
  exit 1
fi
echo "[INFO] Tunnel URL found: $PUBLIC_BASE"

cat >"$SHARE_NOTE_FILE" <<EOF
ChatGPT Proxy Public Share (Quick Tunnel)
=========================================
API Endpoint (RisuAI): $PUBLIC_BASE/v1
API Key: $API_KEY
Model example: gpt-4o

Quick test URL:
$PUBLIC_BASE/status

Important:
- Keep this terminal open while sharing.
- URL changes every time you restart.
- To stop sharing, run ./5_stop_public_share.sh
EOF

echo "[INFO] Share file created: $SHARE_NOTE_FILE"

if ! wait_public_check "$PUBLIC_BASE" "$API_KEY"; then
  echo "[WARN] Public /status check failed now. URL may still become reachable in 10-30s."
fi

echo
echo "[OK] Public share is ready."
echo "URL: $PUBLIC_BASE/v1"
echo "API Key: $API_KEY"
echo
cat "$SHARE_NOTE_FILE"
echo
echo "Press Ctrl+C to stop both server and tunnel."

while true; do
  sleep 2
  if [ "$STARTED_SERVER" -eq 1 ] && [ -n "${SERVER_PID:-}" ] && ! is_pid_running "$SERVER_PID"; then
    echo "[ERROR] Local proxy process exited unexpectedly."
    exit 1
  fi
  if [ -n "${TUNNEL_PID:-}" ] && ! is_pid_running "$TUNNEL_PID"; then
    echo "[ERROR] cloudflared process exited unexpectedly."
    exit 1
  fi
done
