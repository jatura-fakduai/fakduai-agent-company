#!/usr/bin/env bash
set -euo pipefail

# Start the dashboard as a detached process that survives the caller session.
#
# Usage:
#   ./scripts/dashboard-detached.sh
#   ./scripts/dashboard-detached.sh --port 8091 --interval 10

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PORT="${PORT:-8090}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-5}"
SERVE_DIR="${SERVE_DIR:-/tmp/openclaw-dashboard}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      PORT="${2:?Missing value for --port}"
      shift 2
      ;;
    --interval)
      REFRESH_INTERVAL="${2:?Missing value for --interval}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run ./scripts/dashboard-detached.sh --help" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$SERVE_DIR"

existing_pid="$(pgrep -f "^python3 -m http.server ${PORT}$" | head -1 || true)"
if [ -n "$existing_pid" ]; then
  if curl -fsS "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
    echo "$existing_pid" > "$SERVE_DIR/server.pid"
    echo "Dashboard already running: http://127.0.0.1:${PORT} (pid ${existing_pid})"
    exit 0
  fi
  kill "$existing_pid" 2>/dev/null || true
fi

setsid -f bash -c "
  cd '$REPO_ROOT'
  exec ./scripts/dashboard.sh --port '$PORT' --interval '$REFRESH_INTERVAL' >> '$SERVE_DIR/server.log' 2>&1
"

sleep 2
pid="$(pgrep -f "^python3 -m http.server ${PORT}$" | head -1 || true)"
if [ -z "$pid" ]; then
  echo "Dashboard failed to start. Last log lines:" >&2
  tail -40 "$SERVE_DIR/server.log" >&2 || true
  exit 1
fi

echo "$pid" > "$SERVE_DIR/server.pid"
curl -fsS "http://127.0.0.1:${PORT}" >/dev/null
echo "Dashboard: http://127.0.0.1:${PORT} (pid ${pid})"
