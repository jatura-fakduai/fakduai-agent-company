# Automatic Agent Routing

This project now includes a lightweight orchestration layer for Pinto Valley workflows.

It does not make agents magically share one brain. It gives them a concrete routing path, shared workflow folder, and handoff command so each agent can pass work to the next role without the human manually chasing every step.

## Start a Workflow

```bash
./scripts/start-workflow.sh "Build the customer login flow"
```

The script creates a workflow folder under:

```text
~/.openclaw/shared/company-workflows/<workflow-id>/
```

Then it sends the objective to `pm` with instructions to:

1. Create a scoped plan.
2. Save artifacts in the workflow folder.
3. Route the first handoff to `designer`.
4. Track status in `STATUS.md`.

## Route a Handoff

Agents can send structured handoffs with:

```bash
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff body>"
```

Or with stdin:

```bash
cat handoff.md | ./scripts/route-handoff.sh designer frontend <workflow-id>
cat handoff.md | ./scripts/route-handoff.sh designer backend <workflow-id>
```

Each routed handoff is saved to:

```text
~/.openclaw/shared/company-workflows/<workflow-id>/handoffs/
```

The receiving agent gets a message with the workflow id, handoff file path, and expected next action.

`send-task.sh` uses shared company slots so detached handoffs do not all enter `openclaw agent` at once. The default is `COMPANY_MAX_PARALLEL=2`; set `COMPANY_MAX_PARALLEL=1` for low-resource hosts.

If the OpenClaw runtime does not yet have the target agent registered, `send-task.sh` queues the message under:

```text
~/.openclaw/shared/company-outbox/<agent-id>/
```

The dashboard activity feed shows queued messages so work remains visible instead of failing silently.

## Main Sequence

```text
PM -> Solution Designer -> Frontend + Backend -> QA -> Tech Lead
```

Expected routing:

- `pm` routes scope and plan to `designer`.
- `designer` routes build-ready specs to `frontend` and `backend`, respecting the company concurrency limit.
- `frontend` and `backend` route implementation evidence to `qa`.
- `qa` validates browser-facing flows with Playwright and routes pass/fail release evidence to `techlead`.
- `qa` may route reproducible bugs directly back to `frontend` or `backend`.
- Any role may escalate unresolved blockers to `pm`.

## Handoff Requirements

Every routed handoff must include:

- Task
- Why now
- Exact target
- Inputs available
- Expected output
- Definition of done
- If blocked

Implementation handoffs must include verification expectations. Browser-facing QA handoffs must include Playwright evidence unless Tech Lead documents an exception. QA and Tech Lead handoffs must include evidence.

## Useful Commands

Send any ad-hoc task:

```bash
./scripts/send-task.sh qa "Retest workflow 20260526T023000Z-login after frontend fix"
```

Start from stdin:

```bash
printf "Build a booking dashboard MVP" | ./scripts/start-workflow.sh
```

Use a specific workflow id:

```bash
WORKFLOW_ID=booking-dashboard ./scripts/start-workflow.sh "Build a booking dashboard MVP"
```
