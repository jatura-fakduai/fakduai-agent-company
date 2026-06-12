#!/usr/bin/env bash
set -euo pipefail

# One command for dashboard usage.
#
# Usage:
#   ./scripts/dashboard.sh                 # generate, auto-refresh, serve on 8090
#   ./scripts/dashboard.sh --port 8091     # choose port
#   ./scripts/dashboard.sh --once          # generate data once and exit
#   ./scripts/dashboard.sh --no-refresh    # serve without background refresh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PORT="${PORT:-8090}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-1}"
AUTO_REFRESH="${AUTO_REFRESH:-1}"
STALE_AFTER_SECONDS="${STALE_AFTER_SECONDS:-10}"

# Hard-coded canonical fallback — always valid inside the sandbox
_CANONICAL_ROOT="/home/node/.openclaw"

# Step 1: choose a default state root (same logic as generate-dashboard.sh).
if [ -n "${OPENCLAW_STATE_DIR:-}" ] && [ -d "${OPENCLAW_STATE_DIR}/shared/agents" ]; then
  DEFAULT_OPENCLAW_HOME="$OPENCLAW_STATE_DIR"
elif [ -d "$_CANONICAL_ROOT/shared/agents" ]; then
  DEFAULT_OPENCLAW_HOME="$_CANONICAL_ROOT"
else
  DEFAULT_OPENCLAW_HOME="$HOME/.openclaw"
fi

SHARED_ROOT="${SHARED_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/agents}"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-workflows}"
OUTBOX_ROOT="${OUTBOX_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-outbox}"
ACTIVITY_ROOT="${ACTIVITY_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-activity}"

# Step 2: if any resolved root does not exist on disk, fall back to canonical.
if [ ! -d "$SHARED_ROOT" ]; then
  if [ -d "$_CANONICAL_ROOT/shared/agents" ]; then
    SHARED_ROOT="$_CANONICAL_ROOT/shared/agents"
  fi
fi
if [ ! -d "$WORKFLOW_ROOT" ]; then
  if [ -d "$_CANONICAL_ROOT/shared/company-workflows" ]; then
    WORKFLOW_ROOT="$_CANONICAL_ROOT/shared/company-workflows"
  fi
fi
if [ ! -d "$OUTBOX_ROOT" ]; then
  if [ -d "$_CANONICAL_ROOT/shared/company-outbox" ]; then
    OUTBOX_ROOT="$_CANONICAL_ROOT/shared/company-outbox"
  fi
fi
if [ ! -d "$ACTIVITY_ROOT" ]; then
  if [ -d "$_CANONICAL_ROOT/shared/company-activity" ]; then
    ACTIVITY_ROOT="$_CANONICAL_ROOT/shared/company-activity"
  fi
fi
ONCE=0

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
    --once)
      ONCE=1
      shift
      ;;
    --no-refresh)
      AUTO_REFRESH=0
      shift
      ;;
    -h|--help)
      sed -n '1,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run ./scripts/dashboard.sh --help" >&2
      exit 1
      ;;
  esac
done

cd "$REPO_ROOT"
export REPO_ROOT SHARED_ROOT WORKFLOW_ROOT OUTBOX_ROOT ACTIVITY_ROOT

# ---- Serve from local /tmp to avoid fakeowner mount cache coherence issues ----
SERVE_DIR="/tmp/openclaw-dashboard"
BUILD_DIR="/tmp/openclaw-dashboard-build"
mkdir -p "$SERVE_DIR/data"

sync_static_ui() {
  # Keep static UI fresh without overwriting generated runtime data.
  cp -a ui/dashboard/index.html "$SERVE_DIR/index.html"
  if [ -d ui/dashboard/assets ]; then
    mkdir -p "$SERVE_DIR/assets"
    cp -a ui/dashboard/assets/. "$SERVE_DIR/assets/" 2>/dev/null || true
  fi
  if [ -f ui/dashboard/data/app-version.json ]; then
    cp -a ui/dashboard/data/app-version.json "$SERVE_DIR/data/app-version.json" 2>/dev/null || true
  fi
  if [ -f ui/dashboard/data/stage-positions.json ]; then
    cp -a ui/dashboard/data/stage-positions.json "$SERVE_DIR/data/stage-positions.json" 2>/dev/null || true
  fi
}

# Helper: generate and copy data to serve dir atomically
generate_and_sync() {
  sync_static_ui
  # Generate outside the mounted repo path to avoid stale root-owned cache files.
  mkdir -p "$BUILD_DIR/data"
  DASHBOARD_DATA_DIR="$BUILD_DIR/data" bash scripts/generate-dashboard.sh "$@"
  # Copy generated JSON to /tmp serve dir atomically
  for f in agents.json activity.json kanban.json artifacts.json token-usage.json; do
    src="$BUILD_DIR/data/$f"
    if [ -f "$src" ]; then
      # Read from Python (same process) to avoid fakeowner read cache, write to /tmp
      python3 -c "
import json, sys
with open('$src') as fh:
    data = json.load(fh)
with open('$SERVE_DIR/data/$f', 'w') as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
"
    fi
  done
  # Copy screenshot and workflow dirs if present
  if [ -d "$BUILD_DIR/data/screenshots" ]; then
    cp -a "$BUILD_DIR/data/screenshots" "$SERVE_DIR/data/" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR/data/workflows" ]; then
    rm -rf "$SERVE_DIR/data/workflows" 2>/dev/null || true
    cp -a "$BUILD_DIR/data/workflows" "$SERVE_DIR/data/" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR/data/docs" ]; then
    cp -a "$BUILD_DIR/data/docs" "$SERVE_DIR/data/" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR/data/artifacts" ]; then
    cp -a "$BUILD_DIR/data/artifacts" "$SERVE_DIR/data/" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR/data/agent-files" ]; then
    rm -rf "$SERVE_DIR/data/agent-files" 2>/dev/null || true
    cp -a "$BUILD_DIR/data/agent-files" "$SERVE_DIR/data/" 2>/dev/null || true
  fi
  python3 -c "
import json, time
with open('$SERVE_DIR/data/refresh-status.json', 'w') as fh:
    json.dump({'ok': True, 'refreshedAtEpoch': time.time(), 'refreshedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}, fh, indent=2)
"
}

echo "==> Generating dashboard data"
generate_and_sync

if [ "$ONCE" = "1" ]; then
  echo "==> Dashboard data generated"
  exit 0
fi

if [ "$AUTO_REFRESH" = "1" ]; then
  echo "==> Auto-refreshing dashboard data every ${REFRESH_INTERVAL}s"
  (while true; do generate_and_sync > "$SERVE_DIR/data/refresh.log" 2>&1; sleep "$REFRESH_INTERVAL"; done) &
  REFRESH_PID=$!
  (
    while true; do
      sleep "$STALE_AFTER_SECONDS"
      if ! kill -0 "$REFRESH_PID" 2>/dev/null; then
        echo "dashboard refresh loop exited; stopping server for restart" >&2
        kill "$$" 2>/dev/null || true
        exit 1
      fi
      if [ -f "$SERVE_DIR/data/refresh-status.json" ]; then
        age=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$SERVE_DIR/data/refresh-status.json')))")
        if [ "$age" -gt "$STALE_AFTER_SECONDS" ]; then
          echo "dashboard refresh data is stale (${age}s); stopping server for restart" >&2
          kill "$$" 2>/dev/null || true
          exit 1
        fi
      fi
    done
  ) &
  WATCHDOG_PID=$!
  trap 'kill "$REFRESH_PID" "$WATCHDOG_PID" 2>/dev/null || true' EXIT INT TERM
fi

echo "==> Dashboard: http://127.0.0.1:$PORT  (served from $SERVE_DIR)"
cd "$SERVE_DIR"
python3 - "$PORT" "$STALE_AFTER_SECONDS" <<'PY' &
import http.server
import json
import os
import socketserver
import sys
import time
from pathlib import Path

port = int(sys.argv[1])
stale_after = int(sys.argv[2])
repo_root = Path(os.environ.get('REPO_ROOT', '')).resolve()
stage_positions_repo_path = repo_root / 'ui' / 'dashboard' / 'data' / 'stage-positions.json'
stage_positions_serve_path = Path('data/stage-positions.json')

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_GET(self):
        if self.path.split('?', 1)[0] == '/healthz':
            self.send_dashboard_health()
            return
        super().do_GET()

    def do_POST(self):
        path = self.path.split('?', 1)[0]
        if path != '/data/stage-positions.json':
            self.send_json_response({'ok': False, 'error': 'Unsupported save target'}, 404)
            return

        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_json_response({'ok': False, 'error': 'Invalid content length'}, 400)
            return
        if size <= 0 or size > 512_000:
            self.send_json_response({'ok': False, 'error': 'Invalid JSON size'}, 400)
            return

        try:
            raw = self.rfile.read(size)
            body = raw.decode('utf-8')
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError('Root value must be an object')
            if not any(key in payload for key in ('base', 'talk', 'meeting', 'routes')):
                raise ValueError('Missing layout sections')
            body = body.rstrip() + '\n'
            stage_positions_repo_path.parent.mkdir(parents=True, exist_ok=True)
            stage_positions_serve_path.parent.mkdir(parents=True, exist_ok=True)
            stage_positions_repo_path.write_text(body, encoding='utf-8')
            stage_positions_serve_path.write_text(body, encoding='utf-8')
        except Exception as exc:
            self.send_json_response({'ok': False, 'error': str(exc)}, 400)
            return

        self.send_json_response({
            'ok': True,
            'path': 'data/stage-positions.json',
            'updatedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        })

    def send_dashboard_health(self):
        data_path = Path('data/agents.json')
        status_path = Path('data/refresh-status.json')
        now = time.time()
        payload = {'ok': False, 'stale': True, 'ageSeconds': None}
        status = 503
        try:
            source = status_path if status_path.exists() else data_path
            age = max(0, int(now - source.stat().st_mtime))
            payload.update({
                'ok': age <= stale_after and data_path.exists(),
                'stale': age > stale_after,
                'ageSeconds': age,
                'dataMtime': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(data_path.stat().st_mtime)) if data_path.exists() else None,
            })
            if payload['ok']:
                status = 200
        except Exception as exc:
            payload['error'] = str(exc)
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json_response(self, payload, status=200):
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

with ReusableTCPServer(('', port), DashboardHandler) as httpd:
    httpd.serve_forever()
PY
SERVER_PID=$!
if [ "$AUTO_REFRESH" = "1" ]; then
  trap 'kill "$REFRESH_PID" "$WATCHDOG_PID" "$SERVER_PID" 2>/dev/null || true' EXIT INT TERM
else
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT INT TERM
fi
wait "$SERVER_PID"
