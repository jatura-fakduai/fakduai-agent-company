#!/usr/bin/env bash
set -euo pipefail

# Send a task to an agent via OpenClaw CLI
# Usage:
#   ./scripts/send-task.sh <agent-id> "<message>"
#   printf "message" | ./scripts/send-task.sh <agent-id>
#
# Runtime safety knobs:
#   COMPANY_MAX_PARALLEL=2      Maximum concurrent company agent sends.
#   COMPANY_SLOT_WAIT=900       Seconds to wait for a free send slot.
#   COMPANY_LOCK_ROOT=...       Directory for cross-process send slots.
#   ACTIVITY_ROOT=...           Directory for dashboard-visible send events.
#   AGENT_TIMEOUT=300           Per-agent OpenClaw timeout.

AGENT="${1:?Usage: send-task.sh <agent-id> '<message>'}"

if [ "${2:-}" ]; then
  MSG="$2"
elif [ ! -t 0 ]; then
  MSG="$(cat)"
else
  echo "ERROR: Message required as an argument or stdin" >&2
  exit 1
fi

echo "Sending to $AGENT"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN=1, not sending via OpenClaw."
  echo "--- message ---"
  printf '%s\n' "$MSG"
  exit 0
fi

ACTIVITY_ROOT="${ACTIVITY_ROOT:-$HOME/.openclaw/shared/company-activity}"
COMPANY_SEND_FROM="${COMPANY_SEND_FROM:-human}"
COMPANY_WORKFLOW_ID="${COMPANY_WORKFLOW_ID:-}"
SEND_ID="${SEND_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$AGENT-$$}"

record_task_event() {
  local delivery="$1"
  local detail="${2:-}"
  mkdir -p "$ACTIVITY_ROOT" || return 0
  python3 - "$ACTIVITY_ROOT/task-sends.ndjson" "$SEND_ID" "$COMPANY_SEND_FROM" "$AGENT" "$COMPANY_WORKFLOW_ID" "$delivery" "$detail" "$MSG" <<'PY' || true
import datetime
import json
import re
import sys

path, send_id, sender, agent, workflow_id, delivery, detail, message = sys.argv[1:9]

def section(text, heading):
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

summary = (
    section(message, "Task")
    or section(message, "Objective")
    or section(message, "Expected Output")
    or next(
        (
            ln.strip("# ").strip()
            for ln in message.splitlines()
            if ln.strip()
            and not ln.lstrip().startswith("-")
            and not re.match(r"^(Workflow ID|Workflow file|Artifact directory|Handoff file):", ln.strip(), re.I)
        ),
        "",
    )
)
event = {
    "ts": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "sendId": send_id,
    "workflowId": workflow_id,
    "kind": "task_sent",
    "type": "task_sent",
    "from": sender,
    "to": agent,
    "delivery": delivery,
    "detail": detail,
    "summary": summary[:240] or f"Task sent to {agent}",
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
}

record_task_event "sending" "queued for OpenClaw delivery"

run_with_timeout() {
  local limit="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$limit" "$@"
  else
    "$@"
  fi
}

COMPANY_MAX_PARALLEL="${COMPANY_MAX_PARALLEL:-2}"
COMPANY_SLOT_WAIT="${COMPANY_SLOT_WAIT:-900}"
COMPANY_LOCK_ROOT="${COMPANY_LOCK_ROOT:-$HOME/.openclaw/shared/company-agent-slots}"
COMPANY_SLOT=""

release_slot() {
  if [ -n "$COMPANY_SLOT" ] && [ -d "$COMPANY_SLOT" ]; then
    rm -rf "$COMPANY_SLOT"
  fi
}

acquire_slot() {
  if [ "$COMPANY_MAX_PARALLEL" = "0" ]; then
    return 0
  fi

  mkdir -p "$COMPANY_LOCK_ROOT"
  local deadline now slot pid_file pid started
  now="$(date +%s)"
  deadline=$((now + COMPANY_SLOT_WAIT))

  while :; do
    slot=1
    while [ "$slot" -le "$COMPANY_MAX_PARALLEL" ]; do
      COMPANY_SLOT="$COMPANY_LOCK_ROOT/slot-$slot"
      if mkdir "$COMPANY_SLOT" 2>/dev/null; then
        {
          echo "pid=$$"
          echo "agent=$AGENT"
          echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } >"$COMPANY_SLOT/owner"
        trap release_slot EXIT INT TERM
        echo "Acquired company agent slot $slot/$COMPANY_MAX_PARALLEL"
        return 0
      fi

      pid_file="$COMPANY_SLOT/owner"
      pid=""
      started=""
      if [ -f "$pid_file" ]; then
        pid="$(sed -n 's/^pid=//p' "$pid_file" | head -n 1)"
        started="$(sed -n 's/^started_at=//p' "$pid_file" | head -n 1)"
      fi
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        echo "Reclaiming stale company agent slot $slot from pid $pid ($started)" >&2
        rm -rf "$COMPANY_SLOT"
        continue
      fi

      slot=$((slot + 1))
    done

    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      echo "ERROR: timed out waiting for company agent slot after ${COMPANY_SLOT_WAIT}s" >&2
      exit 1
    fi
    sleep 2
  done
}

acquire_slot

AGENT_TIMEOUT="${AGENT_TIMEOUT:-300}"
if [ -z "${GATEWAY_TIMEOUT:-}" ]; then
  if [ "$AGENT_TIMEOUT" = "0" ]; then
    GATEWAY_TIMEOUT=0
  else
    GATEWAY_TIMEOUT=$((AGENT_TIMEOUT + 60))
  fi
fi

if run_with_timeout "$GATEWAY_TIMEOUT" openclaw agent --timeout "$AGENT_TIMEOUT" --agent "$AGENT" --message "$MSG"; then
  record_task_event "delivered" "gateway"
  exit 0
fi

echo "WARNING: gateway delivery to $AGENT failed or timed out; retrying locally" >&2

if run_with_timeout "$AGENT_TIMEOUT" openclaw agent --local --timeout "$AGENT_TIMEOUT" --agent "$AGENT" --session-key "agent:${AGENT}:main" --message "$MSG"; then
  record_task_event "delivered" "local"
  exit 0
fi

if [ "${STRICT_SEND:-0}" = "1" ]; then
  record_task_event "failed" "strict send failed"
  exit 1
fi

OUTBOX_ROOT="${OUTBOX_ROOT:-$HOME/.openclaw/shared/company-outbox}"
mkdir -p "$OUTBOX_ROOT/$AGENT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTBOX_FILE="$OUTBOX_ROOT/$AGENT/${STAMP}.md"
cat > "$OUTBOX_FILE" <<EOF
# Queued Agent Message

- agent: $AGENT
- created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- reason: OpenClaw agent delivery failed; queued for dashboard visibility and later retry.

$MSG
EOF

record_task_event "queued" "$OUTBOX_FILE"
echo "WARNING: direct delivery failed; queued message at $OUTBOX_FILE" >&2
