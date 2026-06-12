#!/usr/bin/env bash
set -euo pipefail

# Route a structured handoff from one company agent to another.
#
# Usage:
#   ./scripts/route-handoff.sh <from-agent> <to-agent> <workflow-id> "<handoff>"
#   printf "handoff" | ./scripts/route-handoff.sh <from-agent> <to-agent> <workflow-id>
#
# Delivery is detached by default so the sending agent can continue, but
# scripts/send-task.sh enforces COMPANY_MAX_PARALLEL to avoid CPU spikes when
# one role fans out to several agents.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$HOME/.openclaw/shared/company-workflows}"

FROM="${1:?Usage: route-handoff.sh <from-agent> <to-agent> <workflow-id> '<handoff>'}"
TO="${2:?Missing target agent}"
WORKFLOW_ID="${3:?Missing workflow id}"

if [ "${4:-}" ]; then
  BODY="$4"
elif [ ! -t 0 ]; then
  BODY="$(cat)"
else
  echo "ERROR: Handoff body required as an argument or stdin" >&2
  exit 1
fi

mkdir -p "$WORKFLOW_ROOT/$WORKFLOW_ID/handoffs"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HANDOFF_FILE="$WORKFLOW_ROOT/$WORKFLOW_ID/handoffs/${STAMP}-${FROM}-to-${TO}.md"

cat > "$HANDOFF_FILE" <<EOF
# HANDOFF

- workflow_id: $WORKFLOW_ID
- from: $FROM
- to: $TO
- created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

$BODY
EOF

EVENTS_FILE="$WORKFLOW_ROOT/$WORKFLOW_ID/events.ndjson"
python3 - "$EVENTS_FILE" "$WORKFLOW_ID" "$FROM" "$TO" "$HANDOFF_FILE" "$BODY" <<'PY'
import json, sys, datetime, re
path, workflow_id, from_agent, to_agent, handoff_file, body = sys.argv[1:7]

def first_section(text, heading):
    lines = text.splitlines()
    capture = False
    out = []
    target = "## " + heading.lower()
    for line in lines:
        s = line.strip()
        if s.lower().startswith("## "):
            if capture:
                break
            capture = s.lower() == target
            continue
        if capture and s:
            out.append(s)
    return " ".join(out).strip()

summary = first_section(body, "Task")
if not summary:
    summary = next((ln.strip("# ").strip() for ln in body.splitlines() if ln.strip()), "")
event = {
    "ts": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "workflowId": workflow_id,
    "type": "handoff",
    "from": from_agent,
    "to": to_agent,
    "summary": summary[:240],
    "path": str(handoff_file),
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY

# Keep the receiving agent's shared status file fresh so the dashboard can
# reflect routed work immediately. Do not mark the receiver as "working" here:
# routing proves only that work was queued/delivering, not that the agent has
# started producing evidence. The receiver must update its own STATUS.md to
# "working" after it has a concrete first action or output.
STATUS_ROOT="${SHARED_ROOT:-$HOME/.openclaw/shared/agents}"
TARGET_STATUS="$STATUS_ROOT/$TO/STATUS.md"
if [ -f "$TARGET_STATUS" ]; then
  python3 - "$TARGET_STATUS" "$WORKFLOW_ID" "$FROM" "$HANDOFF_FILE" "$BODY" "delivering" <<'PY'
import datetime, re, sys
from pathlib import Path

status_path = Path(sys.argv[1])
workflow_id = sys.argv[2]
from_agent = sys.argv[3]
handoff_file = sys.argv[4]
body = sys.argv[5]
status_value = sys.argv[6]

text = status_path.read_text(encoding="utf-8")

def replace_field(text, field, value):
    pattern = re.compile(rf'(^-\s*{re.escape(field)}\s*:\s*).*$',
                         re.IGNORECASE | re.MULTILINE)
    if pattern.search(text):
        return pattern.sub(lambda m: f"{m.group(1)}{value}", text, count=1)
    return text.rstrip() + f"\n- {field}: {value}\n"

def extract_section(text, heading):
    lines = text.splitlines()
    capture = False
    buf = []
    target = f"## {heading}".lower()
    for line in lines:
        s = line.strip()
        if s.lower().startswith("## "):
            if capture:
                break
            capture = s.lower() == target
            continue
        if capture and s:
            buf.append(s)
    return " ".join(buf).strip()

next_action = extract_section(body, "Task") or extract_section(body, "Expected Output")
if not next_action:
    next_action = f"Process workflow {workflow_id} handoff from {from_agent}"
next_action = next_action[:240]

summary = extract_section(body, "Definition of Done") or extract_section(body, "Task") or "working on routed handoff"
summary = summary[:240]

text = replace_field(text, "refreshed_at", datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))
text = replace_field(text, "current objective", f"{workflow_id}: {next_action}")
text = replace_field(text, "current status", status_value)
text = replace_field(text, "active blocker", "none")
text = replace_field(text, "next action", next_action)
text = replace_field(text, "last meaningful output", f"handoff queued: {handoff_file}")
text = replace_field(text, "workflow id", workflow_id)

if "- workflow id:" not in text.lower():
    text = text.rstrip() + f"\n- workflow id: {workflow_id}\n"

status_path.write_text(text, encoding="utf-8")
PY
fi

update_delivery_status() {
  local status_value="$1"
  local detail="$2"
  if [ ! -f "$TARGET_STATUS" ]; then
    return 0
  fi
  python3 - "$TARGET_STATUS" "$WORKFLOW_ID" "$HANDOFF_FILE" "$status_value" "$detail" <<'PY' || true
import datetime, re, sys
from pathlib import Path

status_path = Path(sys.argv[1])
workflow_id = sys.argv[2]
handoff_file = sys.argv[3]
status_value = sys.argv[4]
detail = sys.argv[5]
text = status_path.read_text(encoding="utf-8")

def replace_field(text, field, value):
    pattern = re.compile(rf'(^-\s*{re.escape(field)}\s*:\s*).*$',
                         re.IGNORECASE | re.MULTILINE)
    if pattern.search(text):
        return pattern.sub(lambda m: f"{m.group(1)}{value}", text, count=1)
    return text.rstrip() + f"\n- {field}: {value}\n"

text = replace_field(text, "refreshed_at", datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))
text = replace_field(text, "current status", status_value)
text = replace_field(text, "active blocker", "none" if status_value.startswith("delivered") else "delivery failed; sender must retry or reassign")
text = replace_field(text, "next action", "receiver must acknowledge handoff with first evidence/status update" if status_value.startswith("delivered") else "sender must inspect delivery log and retry or reassign")
text = replace_field(text, "last meaningful output", f"{detail}: {handoff_file}")
text = replace_field(text, "workflow id", workflow_id)
status_path.write_text(text, encoding="utf-8")
PY
}

MESSAGE="$(cat <<EOF
You have received a handoff from $FROM.

Workflow ID: $WORKFLOW_ID
Handoff file: $HANDOFF_FILE

Read the handoff, update your STATUS.md, do the next role-appropriate step, and route the next handoff when your deliverable is ready.

$BODY
EOF
)"

if [ "${ROUTE_DETACHED:-1}" = "1" ]; then
  DELIVERY_LOG_DIR="${DELIVERY_LOG_DIR:-$WORKFLOW_ROOT/$WORKFLOW_ID/delivery-logs}"
  mkdir -p "$DELIVERY_LOG_DIR"
  DELIVERY_LOG="$DELIVERY_LOG_DIR/${STAMP}-${FROM}-to-${TO}.log"
  (
    if COMPANY_SEND_FROM="$FROM" COMPANY_WORKFLOW_ID="$WORKFLOW_ID" "$REPO_ROOT/scripts/send-task.sh" "$TO" "$MESSAGE"; then
      update_delivery_status "delivered_waiting_for_receiver" "delivery succeeded"
    else
      update_delivery_status "delivery_failed" "delivery failed; see $DELIVERY_LOG"
      exit 1
    fi
  ) >"$DELIVERY_LOG" 2>&1 &
  DELIVERY_PID=$!
  echo "Delivery to $TO started in background (pid $DELIVERY_PID, log $DELIVERY_LOG)" >&2
else
  if COMPANY_SEND_FROM="$FROM" COMPANY_WORKFLOW_ID="$WORKFLOW_ID" "$REPO_ROOT/scripts/send-task.sh" "$TO" "$MESSAGE"; then
    update_delivery_status "delivered_waiting_for_receiver" "delivery succeeded"
  else
    update_delivery_status "delivery_failed" "delivery failed during synchronous route"
    exit 1
  fi
fi

echo "$HANDOFF_FILE"
