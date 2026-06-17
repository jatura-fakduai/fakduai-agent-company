# Workflow Monitor Utility

PM owns company-agent control-plane health: delivery state, receiver acknowledgement, stale `working`, and token-heavy polling. The monitor script is a quiet utility PM can run for compact checks; it is not a separate office role.

## Purpose
PM should not spend most tokens polling every raw log. The monitor utility produces compact escalation summaries and marks delivery/control-plane failures early.

## Script

```bash
./scripts/monitor-workflows.sh
```

Report only. Reads compact state:
- shared `STATUS.md`
- recent delivery-log metadata
- no source-tree greps
- no large artifact reads

By default, delivery-log checks inspect only the last 120 minutes so old closed workflow logs do not create noisy reports. Override the window with:

```bash
MONITOR_LOG_WINDOW_MINUTES=30 ./scripts/monitor-workflows.sh
```

Apply stale markers:

```bash
./scripts/monitor-workflows.sh --apply
```

Limit to one workflow:

```bash
./scripts/monitor-workflows.sh --workflow <workflow-id> --apply
```

## Stale Rules
- `delivering` older than 3 minutes -> stale delivery.
- `delivered_waiting_for_receiver` older than 5 minutes -> stale receiver acknowledgement.
- `delivery_failed` -> retry or reassign.
- `working` older than 20 minutes without meaningful evidence -> stale work.
- `blocked` older than 30 minutes -> aging blocker.

## Required PM Behavior
- Do not repeatedly wake the same stale agent more than once without new evidence.
- After one reset with no acknowledgement, reassign/split/escalate.
- Keep periodic reports compact: percent, owner, latest evidence, blocker, next action.
- Inspect large artifacts/source only after a status change, explicit blocker, or user request.

## Dashboard Meaning
- `delivering`: send in progress, not active work.
- `delivered_waiting_for_receiver`: delivered but not acknowledged, not active work.
- `working`: receiver acknowledged and has started a concrete action with evidence.
- `delivery_failed`: control-plane failure, not role failure.
