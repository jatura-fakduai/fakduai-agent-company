# Work Reality Check

Dashboard `Doing` must mean an agent is actually making progress, not merely holding a `working` status.

## Problem

`STATUS.md` is self-reported. It can say `working` even when:

- the agent session failed
- no artifact was produced
- the promised output path does not exist
- the only activity was a status update
- the delivery log never moved past "Sending to ..."

Therefore the dashboard must not trust `current status: working` by itself.

## Permanent Signal Model

Use three evidence layers.

### 1. Status Layer

Read canonical shared `STATUS.md`:

- `current status`
- `refreshed_at`
- `current objective`
- `active blocker`
- `next action`
- `last meaningful output`
- `workflow id`

This answers: what does the agent claim?

### 2. Runtime Layer

Read OpenClaw session health for the agent:

- latest session status: `running`, `completed`, `failed`, `aborted`
- latest session updated time
- whether the latest session ended after a tool call without final output
- transcript path when available

This answers: did the agent actually run, fail, or go silent?

### 3. Artifact Layer

Read workflow output evidence:

- expected artifact path from handoff/status when present
- workflow `artifacts/` file count and newest mtime
- workflow `events.ndjson` entries after assignment
- handoff or route events from the owner
- meaningful output file size greater than a tiny placeholder

This answers: did work produce something useful?

## Dashboard Labels

Only show small labels on Doing cards:

- `Active`: status is working and there is fresh runtime/artifact evidence.
- `No proof`: status is working but no new artifact/event/session output exists.
- `Failed`: latest session failed after the work was assigned.
- `Stale`: status is working but no refresh/output after timeout.
- `Blocked`: active blocker exists.

Avoid large panels. The dashboard should stay simple.

## Rules

- `working` + no artifact/event/session output after 10 minutes -> `No proof`.
- `working` + latest session `failed` after assignment -> `Failed`, and PM must mark agent blocked.
- `working` + promised artifact path missing after ETA -> `No proof` or `Failed` depending on session state.
- `delivering` with send-only delivery log after 5 minutes -> delivery failure, not active work.
- `blocked` must move/report to Talk immediately.
- PM should not nudge the same stale owner repeatedly. After one recovery attempt with no output, reassign or escalate.

## Monitor Implementation

Use `scripts/monitor-workflows.sh` with optional deep checks:

```bash
./scripts/monitor-workflows.sh --workflow <id> --deep
./scripts/monitor-workflows.sh --workflow <id> --deep --apply
```

Deep checks:

- scan recent OpenClaw session metadata from each agent's `sessions.json`
- detect latest failed/aborted session after assignment
- detect missing promised artifact paths for the active workflow
- detect workflow artifact/event inactivity
- emit compact JSON problems for dashboard and PM without raw STATUS body leakage

`--apply` may mark `STATUS.md` as blocked only when the evidence is objective:

- failed session after assignment
- missing promised artifact after ETA
- send-only delivery log beyond threshold

## PM Behavior

When a founder asks "is the team actually working?", PM must answer from the three layers:

1. claimed status
2. session/runtime evidence
3. artifact/output evidence

Do not report "working" from status alone.
