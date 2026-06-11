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

if timeout "$GATEWAY_TIMEOUT" openclaw agent --timeout "$AGENT_TIMEOUT" --agent "$AGENT" --message "$MSG"; then
  exit 0
fi

echo "WARNING: gateway delivery to $AGENT failed or timed out; retrying locally" >&2

if timeout "$AGENT_TIMEOUT" openclaw agent --local --timeout "$AGENT_TIMEOUT" --agent "$AGENT" --session-key "agent:${AGENT}:main" --message "$MSG"; then
  exit 0
fi

if [ "${STRICT_SEND:-0}" = "1" ]; then
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

echo "WARNING: direct delivery failed; queued message at $OUTBOX_FILE" >&2
