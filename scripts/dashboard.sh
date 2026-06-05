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
export REPO_ROOT SHARED_ROOT WORKFLOW_ROOT OUTBOX_ROOT

# ---- Serve from local /tmp to avoid fakeowner mount cache coherence issues ----
SERVE_DIR="/tmp/openclaw-dashboard"
BUILD_DIR="/tmp/openclaw-dashboard-build"
mkdir -p "$SERVE_DIR/data"
# Copy static UI assets to serve dir (only if not already there or if changed)
if [ ! -d "$SERVE_DIR/css" ] || [ ui/dashboard/index.html -nt "$SERVE_DIR/index.html" ]; then
  cp -a ui/dashboard/* "$SERVE_DIR/" 2>/dev/null || true
fi

# Helper: generate and copy data to serve dir atomically
generate_and_sync() {
  # Generate outside the mounted repo path to avoid stale root-owned cache files.
  mkdir -p "$BUILD_DIR/data"
  DASHBOARD_DATA_DIR="$BUILD_DIR/data" bash scripts/generate-dashboard.sh "$@"
  # Copy generated JSON to /tmp serve dir atomically
  for f in agents.json activity.json kanban.json artifacts.json; do
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
  trap 'kill "$REFRESH_PID" 2>/dev/null || true' EXIT INT TERM
fi

echo "==> Dashboard: http://127.0.0.1:$PORT  (served from $SERVE_DIR)"
cd "$SERVE_DIR"
exec python3 -m http.server "$PORT"
