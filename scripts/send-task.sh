#!/usr/bin/env bash
set -euo pipefail

# Send a task to an agent via OpenClaw CLI
# Usage:
#   ./scripts/send-task.sh <agent-id> "<message>"
#   printf "message" | ./scripts/send-task.sh <agent-id>

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

AGENT_TIMEOUT="${AGENT_TIMEOUT:-600}"
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
