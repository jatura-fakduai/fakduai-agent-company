#!/usr/bin/env bash
set -euo pipefail

# Regression guard for dashboard source-root selection.
#
# It intentionally injects stale host roots and verifies both generation paths
# still resolve to the canonical runtime shared data under /home/node/.openclaw.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ -z "${CANONICAL_ROOT:-}" ]; then
  if [ -d "/data/.openclaw/shared/agents" ]; then
    CANONICAL_ROOT="/data/.openclaw"
  elif [ -d "/home/node/.openclaw/shared/agents" ]; then
    CANONICAL_ROOT="/home/node/.openclaw"
  else
    CANONICAL_ROOT="${HOME:-/data}/.openclaw"
  fi
fi
BAD_ROOT="${BAD_ROOT:-${HOME:-/tmp}/.openclaw-stale}"
OUT_DIR="$REPO_ROOT/ui/dashboard/data"
SERVE_DIR="/tmp/openclaw-dashboard"

run_with_stale_roots() {
  env \
    OPENCLAW_STATE_DIR="$BAD_ROOT" \
    SHARED_ROOT="$BAD_ROOT/shared/agents" \
    WORKFLOW_ROOT="$BAD_ROOT/shared/company-workflows" \
    OUTBOX_ROOT="$BAD_ROOT/shared/company-outbox" \
    "$@"
}

validate_dashboard_data() {
  local label="$1"
  local data_dir="$2"

  python3 - "$label" "$data_dir" "$CANONICAL_ROOT" "$BAD_ROOT" <<'PY'
import json
import sys
from pathlib import Path

label, data_dir, canonical_root, bad_root = sys.argv[1:5]
data_dir = Path(data_dir)

files = {
    "agents": data_dir / "agents.json",
    "kanban": data_dir / "kanban.json",
    "activity": data_dir / "activity.json",
}

for name, path in files.items():
    if not path.exists():
        raise SystemExit(f"{label}: missing {path}")

agents = json.loads(files["agents"].read_text(encoding="utf-8"))
kanban = json.loads(files["kanban"].read_text(encoding="utf-8"))
activity = json.loads(files["activity"].read_text(encoding="utf-8"))
required = {"pm", "designer", "frontend", "backend", "qa", "techlead"}

checks = [
    ("agents", len(agents.get("agents", []))),
    ("kanban cards", len(kanban.get("cards", []))),
    ("activities", len(activity.get("activities", []))),
]
for name, count in checks:
    if count <= 0:
        raise SystemExit(f"{label}: expected non-empty {name}, got {count}")

agent_ids = {item.get("id") for item in agents.get("agents", [])}
card_ids = {item.get("ownerId") or item.get("id") for item in kanban.get("cards", [])}
missing_agents = sorted(required - agent_ids)
missing_cards = sorted(required - card_ids)
if missing_agents:
    raise SystemExit(f"{label}: missing required agents: {', '.join(missing_agents)}")
if missing_cards:
    raise SystemExit(f"{label}: missing required kanban cards: {', '.join(missing_cards)}")

for name, payload in (("agents", agents), ("kanban", kanban), ("activity", activity)):
    roots = payload.get("meta", {}).get("sourceRoots", {})
    if not roots:
        raise SystemExit(f"{label}: {name}.meta.sourceRoots missing")
    for root_name, value in roots.items():
        if value.startswith(bad_root):
            raise SystemExit(f"{label}: {name}.meta.sourceRoots.{root_name} kept stale root {value}")
    shared_agents = roots.get("sharedAgents")
    workflows = roots.get("workflows")
    if shared_agents != f"{canonical_root}/shared/agents":
        raise SystemExit(f"{label}: sharedAgents root mismatch: {shared_agents}")
    if workflows != f"{canonical_root}/shared/company-workflows":
        raise SystemExit(f"{label}: workflows root mismatch: {workflows}")

print(
    f"{label}: PASS "
    f"agents={len(agents['agents'])} "
    f"cards={len(kanban['cards'])} "
    f"activities={len(activity['activities'])} "
    f"root={canonical_root}/shared"
)
PY
}

if [ ! -d "$CANONICAL_ROOT/shared/agents" ]; then
  echo "ERROR: canonical shared agents root not found: $CANONICAL_ROOT/shared/agents" >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "==> Smoke: generate-dashboard.sh with stale injected roots"
run_with_stale_roots bash scripts/generate-dashboard.sh >/tmp/openclaw-dashboard-root-smoke-generate.log
validate_dashboard_data "generate-dashboard.sh" "$OUT_DIR"

echo "==> Smoke: dashboard.sh --once with stale injected roots"
run_with_stale_roots bash scripts/dashboard.sh --once >/tmp/openclaw-dashboard-root-smoke-dashboard.log
validate_dashboard_data "dashboard.sh --once mounted data" "$OUT_DIR"
validate_dashboard_data "dashboard.sh --once served data" "$SERVE_DIR/data"

echo "==> Dashboard root-source smoke passed"
