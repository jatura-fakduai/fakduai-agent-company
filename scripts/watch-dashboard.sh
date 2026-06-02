#!/usr/bin/env bash
# Auto-regenerate dashboard data every N seconds
# Run this alongside the HTTP server to keep Kanban + agent status fresh
set -euo pipefail
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INTERVAL="${INTERVAL:-5}"

echo "==> Watching dashboard data (every ${INTERVAL}s)..."
echo "    Press Ctrl+C to stop"

LOG_DIR="$REPO_ROOT/.runtime"
mkdir -p "$LOG_DIR"

while true; do
    bash "$REPO_ROOT/scripts/generate-dashboard.sh" >> "$LOG_DIR/watch-dashboard.log" 2>&1 || true
    sleep "$INTERVAL"
done
