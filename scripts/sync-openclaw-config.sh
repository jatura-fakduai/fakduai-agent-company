#!/usr/bin/env bash
set -euo pipefail

# Idempotently merge company agents into OpenClaw config.
#
# Usage:
#   ./scripts/sync-openclaw-config.sh
#
# Optional env:
#   CONFIG=./config/office.json
#   OPENCLAW_STATE_DIR=$HOME/.openclaw
#   OPENCLAW_CONFIG=/path/to/openclaw.json
#   WORKSPACE_ROOT=$OPENCLAW_STATE_DIR
#   COMPANY_AGENT_MODEL=openai-codex/gpt-5.5
#   SYNC_AUTH_PROFILES=1

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="${CONFIG:-$REPO_ROOT/config/office.json}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_STATE_DIR/openclaw.json}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$OPENCLAW_STATE_DIR}"
GENERATED_DIR="${GENERATED_DIR:-$REPO_ROOT/generated}"
CONFIG_SNIPPET="${CONFIG_SNIPPET:-$GENERATED_DIR/openclaw-agents.json}"
SYNC_AUTH_PROFILES="${SYNC_AUTH_PROFILES:-1}"

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: Company config not found: $CONFIG" >&2
  exit 1
fi

if [ ! -f "$OPENCLAW_CONFIG" ]; then
  echo "ERROR: OpenClaw config not found: $OPENCLAW_CONFIG" >&2
  echo "Run OpenClaw setup/onboarding first, then rerun this script." >&2
  exit 1
fi

mkdir -p "$GENERATED_DIR"

python3 - "$CONFIG" "$OPENCLAW_CONFIG" "$WORKSPACE_ROOT" "$CONFIG_SNIPPET" <<'PY'
import copy
import datetime
import json
import os
import sys
from pathlib import Path

company_config_path, openclaw_config_path, workspace_root, snippet_path = sys.argv[1:5]
company_config = json.loads(Path(company_config_path).read_text(encoding="utf-8"))
config_path = Path(openclaw_config_path)
openclaw_config = json.loads(config_path.read_text(encoding="utf-8"))

agent_ids = [a["id"] for a in company_config.get("agents", [])]
if not agent_ids:
    raise SystemExit("ERROR: config/office.json has no agents")

existing_company_model = None
for item in openclaw_config.get("agents", {}).get("list", []):
    if isinstance(item, dict) and item.get("id") in agent_ids:
        existing_company_model = item.get("model", {}).get("primary")
        if existing_company_model:
            break

default_model = (
    os.environ.get("COMPANY_AGENT_MODEL")
    or existing_company_model
    or openclaw_config.get("agents", {}).get("defaults", {}).get("model", {}).get("primary")
    or "openai-codex/gpt-5.5"
)

def model_block(model_ref):
    return {
        "model": {"primary": model_ref},
        "models": {model_ref: {}},
    }

company_agents = []
for agent_id in agent_ids:
    entry = {
        "id": agent_id,
        "name": agent_id,
        "workspace": f"{workspace_root}/workspace-{agent_id}",
    }
    entry.update(model_block(default_model))
    company_agents.append(entry)

snippet = {
    "agents": {"list": company_agents},
    "tools": {
        "sessions": {"visibility": "all"},
        "agentToAgent": {
            "enabled": True,
            "allow": ["main", *agent_ids],
        },
    },
}
Path(snippet_path).write_text(json.dumps(snippet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

cfg = copy.deepcopy(openclaw_config)
cfg.setdefault("agents", {})
cfg["agents"].setdefault("list", [])

existing = {
    item.get("id"): i
    for i, item in enumerate(cfg["agents"]["list"])
    if isinstance(item, dict) and item.get("id")
}
for agent in company_agents:
    agent_id = agent["id"]
    if agent_id in existing:
        merged = copy.deepcopy(cfg["agents"]["list"][existing[agent_id]])
        merged.update(agent)
        cfg["agents"]["list"][existing[agent_id]] = merged
    else:
        cfg["agents"]["list"].append(agent)

tools = cfg.setdefault("tools", {})
tools.setdefault("sessions", {})
tools["sessions"]["visibility"] = "all"
tools.setdefault("agentToAgent", {})
tools["agentToAgent"]["enabled"] = True
allow = tools["agentToAgent"].setdefault("allow", [])
if not isinstance(allow, list):
    allow = []
for agent_id in ["main", *agent_ids]:
    if agent_id not in allow:
        allow.append(agent_id)
tools["agentToAgent"]["allow"] = allow

if cfg != openclaw_config:
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    backup = config_path.with_name(config_path.name + f".bak-company-sync-{stamp}")
    backup.write_text(json.dumps(openclaw_config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Updated {config_path}")
    print(f"Backup: {backup}")
else:
    print(f"No config changes needed: {config_path}")

print(f"Generated snippet: {snippet_path}")
print(f"Company model: {default_model}")
PY

if [ "$SYNC_AUTH_PROFILES" = "1" ] && [ -f "$OPENCLAW_STATE_DIR/agents/main/agent/auth-profiles.json" ]; then
  while IFS= read -r AGENT_ID; do
    [ -n "$AGENT_ID" ] || continue
    AGENT_DIR="$OPENCLAW_STATE_DIR/agents/$AGENT_ID/agent"
    mkdir -p "$AGENT_DIR"
    cp "$OPENCLAW_STATE_DIR/agents/main/agent/auth-profiles.json" "$AGENT_DIR/auth-profiles.json"
    if [ -f "$OPENCLAW_STATE_DIR/agents/main/agent/models.json" ]; then
      cp "$OPENCLAW_STATE_DIR/agents/main/agent/models.json" "$AGENT_DIR/models.json"
    fi
  done < <(python3 - "$CONFIG" <<'PY'
import json, sys
for agent in json.load(open(sys.argv[1], encoding="utf-8")).get("agents", []):
    print(agent["id"])
PY
)
  echo "Synced main auth/model profiles to company agents."
fi

if command -v openclaw >/dev/null 2>&1; then
  openclaw config validate >/dev/null
  echo "OpenClaw config validated."
fi

echo "Restart or recreate the OpenClaw gateway/container so the running gateway loads the updated agent list."
