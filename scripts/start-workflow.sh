#!/usr/bin/env bash
set -euo pipefail

# Start a Pinto Valley multi-agent workflow.
#
# Usage:
#   ./scripts/start-workflow.sh "<objective>"
#   printf "objective" | ./scripts/start-workflow.sh
#
# Optional:
#   WORKFLOW_ID=my-id ./scripts/start-workflow.sh "<objective>"
#   WORKFLOW_ROOT=/path/to/workflows ./scripts/start-workflow.sh "<objective>"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$HOME/.openclaw/shared/company-workflows}"
WORKFLOW_ID="${WORKFLOW_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')}"

if [ "${1:-}" ]; then
  OBJECTIVE="$1"
elif [ ! -t 0 ]; then
  OBJECTIVE="$(cat)"
else
  echo "ERROR: Objective required as an argument or stdin" >&2
  exit 1
fi

WORKFLOW_DIR="$WORKFLOW_ROOT/$WORKFLOW_ID"
mkdir -p "$WORKFLOW_DIR/handoffs" "$WORKFLOW_DIR/artifacts"

cat > "$WORKFLOW_DIR/WORKFLOW.md" <<EOF
# Workflow: $WORKFLOW_ID

## Objective
$OBJECTIVE

## Main Sequence
PM -> Solution Designer -> Frontend + Backend -> QA -> Tech Lead

## Routing Rules
- PM owns scope, task breakdown, dependencies, and follow-up.
- Solution Designer turns PM scope into build-ready specs.
- Frontend and Backend implement their slices and provide evidence.
- QA validates acceptance criteria and files reproducible bugs when needed.
- Tech Lead reviews evidence and approves, conditionally approves, or blocks release.
- Respect company send concurrency. Default COMPANY_MAX_PARALLEL=2; use sequential routing when a host is resource constrained.

## Created
$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

EVENTS_FILE="$WORKFLOW_DIR/events.ndjson"
python3 - "$EVENTS_FILE" "$WORKFLOW_ID" "$OBJECTIVE" <<'PY'
import json, sys, datetime
path, workflow_id, objective = sys.argv[1:4]
event = {
    "ts": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "workflowId": workflow_id,
    "type": "workflow_started",
    "from": "human",
    "to": "pm",
    "summary": objective[:240],
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PY

PM_MESSAGE="$(cat <<EOF
You are starting a Pinto Valley multi-agent workflow.

Workflow ID: $WORKFLOW_ID
Workflow file: $WORKFLOW_DIR/WORKFLOW.md
Artifact directory: $WORKFLOW_DIR/artifacts

Objective:
$OBJECTIVE

Your job:
1. Clarify the scope, assumptions, constraints, success criteria, and non-goals.
2. Create a phased implementation plan with owners, dependencies, risk, and definition of done.
3. Save the plan under $WORKFLOW_DIR/artifacts/pm-plan.md.
4. Send the first structured handoff to Solution Designer using:
   $REPO_ROOT/scripts/route-handoff.sh pm designer $WORKFLOW_ID "<handoff>"
5. Update STATUS.md with the workflow id, current state, next action, and blocker if any.

Use the standard HANDOFF format. Do not wait silently if information is missing; identify the missing input and route/escalate it.
Do not fan out to every role at once. The company routing scripts throttle sends with COMPANY_MAX_PARALLEL, which defaults to 2.
EOF
)"

COMPANY_SEND_FROM="human" COMPANY_WORKFLOW_ID="$WORKFLOW_ID" "$REPO_ROOT/scripts/send-task.sh" pm "$PM_MESSAGE"

echo "Started workflow: $WORKFLOW_ID"
echo "Workflow file: $WORKFLOW_DIR/WORKFLOW.md"
