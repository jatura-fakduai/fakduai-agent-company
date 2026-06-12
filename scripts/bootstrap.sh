#!/usr/bin/env bash
set -euo pipefail

# Bootstrap — create workspaces, status files, and dashboard data from config
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="${CONFIG:-$REPO_ROOT/config/office.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/.openclaw}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$WORKSPACE_ROOT}"
SHARED_ROOT="${SHARED_ROOT:-$OPENCLAW_STATE_DIR/shared/agents}"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$OPENCLAW_STATE_DIR/shared/company-workflows}"
OUTBOX_ROOT="${OUTBOX_ROOT:-$OPENCLAW_STATE_DIR/shared/company-outbox}"
ACTIVITY_ROOT="${ACTIVITY_ROOT:-$OPENCLAW_STATE_DIR/shared/company-activity}"
GENERATED_DIR="${GENERATED_DIR:-$REPO_ROOT/generated}"
USER_TIMEZONE="${USER_TIMEZONE:-Asia/Bangkok}"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: Config not found at $CONFIG"
  exit 1
fi

echo "==> Reading config from $CONFIG"
AGENTS=$(python3 -c "
import json,sys
c=json.load(open('$CONFIG'))
for a in c.get('agents',[]):
    print(a['id'])
")

DEFAULT_TEMPLATE="$REPO_ROOT/templates/workspaces/default"

mkdir -p "$SHARED_ROOT" "$WORKFLOW_ROOT" "$OUTBOX_ROOT" "$ACTIVITY_ROOT" "$GENERATED_DIR"

echo "==> Creating workspaces and status files"
for AGENT_ID in $AGENTS; do
  # Parse agent info
  INFO=$(python3 -c "
import json
c=json.load(open('$CONFIG'))
a = next((x for x in c['agents'] if x['id']=='$AGENT_ID'), None)
if a:
    print(f\"{a['name']}|{a.get('role','')}|{a.get('emoji','')}\")
")

  NAME=$(echo "$INFO" | cut -d'|' -f1)
  ROLE=$(echo "$INFO" | cut -d'|' -f2)
  EMOJI=$(echo "$INFO" | cut -d'|' -f3)

  WS="$WORKSPACE_ROOT/workspace-$AGENT_ID"
  mkdir -p "$WS" "$WS/memory"

  ROLE_TEMPLATE="$REPO_ROOT/templates/workspaces/$AGENT_ID"

  # Copy templates with placeholder substitution
  for F in SOUL.md AGENTS.md IDENTITY.md TOOLS.md; do
    TEMPLATE="$DEFAULT_TEMPLATE"
    if [ -f "$ROLE_TEMPLATE/$F" ]; then
      TEMPLATE="$ROLE_TEMPLATE"
    fi
    if [ -f "$TEMPLATE/$F" ]; then
      python3 - "$TEMPLATE/$F" "$WS/$F" "$NAME" "$ROLE" "$EMOJI" <<'PY'
import sys
src, dst, name, role, emoji = sys.argv[1:6]
text = open(src, 'r', encoding='utf-8').read()
text = text.replace('{{NAME}}', name).replace('{{ROLE}}', role).replace('{{EMOJI}}', emoji)
open(dst, 'w', encoding='utf-8').write(text)
PY
    fi
  done

  # Create USER.md
  cat > "$WS/USER.md" <<UEOF
# USER.md

- **Name:** (set during first chat)
- **Timezone:** $USER_TIMEZONE
UEOF

  # Create shared status
  mkdir -p "$SHARED_ROOT/$AGENT_ID"
  cat > "$SHARED_ROOT/$AGENT_ID/STATUS.md" <<SEOF
# STATUS
- refreshed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- agent_id: $AGENT_ID
- current objective: initialized and waiting for tasks
- current status: idle
- active blocker: none
- next action: waiting for assignment
- last meaningful output: agent initialized
SEOF

  echo "  ✅ $EMOJI $NAME ($AGENT_ID) → $WS"
done

CONFIG_SNIPPET="$GENERATED_DIR/openclaw-agents.json"
python3 - "$CONFIG" "$WORKSPACE_ROOT" "$CONFIG_SNIPPET" <<'PY'
import json
import sys

config_path, workspace_root, out_path = sys.argv[1:4]
config = json.load(open(config_path, encoding='utf-8'))
agent_ids = [a['id'] for a in config.get('agents', [])]
snippet = {
    "agents": {
        "list": [
            {
                "id": agent_id,
                "name": agent_id,
                "workspace": f"{workspace_root}/workspace-{agent_id}",
            }
            for agent_id in agent_ids
        ]
    },
    "tools": {
        "sessions": {"visibility": "all"},
        "agentToAgent": {
            "enabled": True,
            "allow": ["main", *agent_ids],
        },
    },
}
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(snippet, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

# Generate dashboard data
echo "==> Generating dashboard data"
export OPENCLAW_STATE_DIR SHARED_ROOT WORKFLOW_ROOT OUTBOX_ROOT ACTIVITY_ROOT
bash "$REPO_ROOT/scripts/generate-dashboard.sh"

if [ "${SKIP_OPENCLAW_SYNC:-0}" != "1" ]; then
  echo "==> Syncing OpenClaw agent config"
  OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
    WORKSPACE_ROOT="$WORKSPACE_ROOT" \
    CONFIG="$CONFIG" \
    bash "$REPO_ROOT/scripts/sync-openclaw-config.sh"
else
  echo "==> Skipping OpenClaw config sync because SKIP_OPENCLAW_SYNC=1"
fi

echo ""
echo "==> Bootstrap complete!"
echo "    Agents created: $(echo "$AGENTS" | wc -l)"
echo ""
echo "    Next steps:"
echo "    1. Restart/recreate the OpenClaw gateway or container"
echo "    2. ./scripts/dashboard.sh"
echo ""
echo "    Re-run ./scripts/sync-openclaw-config.sh after changing config/office.json."
