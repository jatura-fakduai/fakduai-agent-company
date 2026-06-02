#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INTERVAL="${1:-1}"
echo "Auto-refreshing every ${INTERVAL}s (Ctrl+C to stop)"
while true; do
  "$REPO_ROOT/scripts/dashboard.sh" --once >/dev/null
  sleep "$INTERVAL"
done
