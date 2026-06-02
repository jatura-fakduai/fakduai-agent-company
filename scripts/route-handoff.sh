#!/usr/bin/env bash
set -euo pipefail

# Route a structured handoff from one company agent to another.
#
# Usage:
#   ./scripts/route-handoff.sh <from-agent> <to-agent> <workflow-id> "<handoff>"
#   printf "handoff" | ./scripts/route-handoff.sh <from-agent> <to-agent> <workflow-id>

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
    "$REPO_ROOT/scripts/send-task.sh" "$TO" "$MESSAGE"
  ) >"$DELIVERY_LOG" 2>&1 &
  DELIVERY_PID=$!
  echo "Delivery to $TO started in background (pid $DELIVERY_PID, log $DELIVERY_LOG)" >&2
else
  "$REPO_ROOT/scripts/send-task.sh" "$TO" "$MESSAGE"
fi

echo "$HANDOFF_FILE"
