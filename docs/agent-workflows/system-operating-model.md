# System Operating Model

## Pinto Valley Team - 6 Agents

```text
Project Manager
  -> Solution Designer
  -> Frontend Engineer + Backend Engineer
  -> QA Engineer
  -> Tech Lead
  -> Release / Deploy
```

The sequence above is the main delivery path. Parallel work is allowed, but it must respect the company send throttle. On small hosts, prefer one active role at a time; on larger hosts, use at most two active role agents unless a human explicitly raises `COMPANY_MAX_PARALLEL`.

Agents may still talk directly when it removes delay:

- QA finds a bug -> route it directly to Frontend or Backend.
- Frontend needs UX clarification -> route it to Solution Designer.
- Backend hits an architecture or migration risk -> route it to Tech Lead.
- Any unresolved blocker -> escalate to PM.

## Automation Layer

Use the routing scripts when a task should move between agents without human relay:

```bash
./scripts/start-workflow.sh "Build the customer login flow"
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff>"
```

The routing layer uses `scripts/send-task.sh`, which defaults to `COMPANY_MAX_PARALLEL=2`. This prevents a PM handoff burst from launching every role agent at once and driving local CPU to 100%. Set `COMPANY_MAX_PARALLEL=1` for constrained machines.

Workflow state is stored under:

```text
~/.openclaw/shared/company-workflows/<workflow-id>/
```

## Shared Documents

- `agent-operating-rules.md` - central operating rules
- `automatic-routing.md` - workflow start and handoff routing commands
- `role-specialization-addenda.md` - role-specific depth and artifacts
- `handoff-template.md` - standard cross-role handoff format
- `status-output-examples.md` - role-specific status examples
- `artifact-metadata-schema.md` - evidence and work-item metadata schema

## Core Rules

### 1. One Owner Per Layer

- PM owns scope, dependency tracking, stale work, and escalation.
- Solution Designer owns design, UX flow, contracts, and implementation blueprint.
- Frontend and Backend own implementation quality for their slices.
- QA owns verification quality, Playwright-backed browser validation, and reproducible evidence.
- Tech Lead owns architecture decisions, technical review, and release approval.

### 2. Do Not Hold Work Silently

When meaningful progress happens:

- Update `STATUS.md`.
- Save the artifact or evidence in the workflow folder when a workflow id exists.
- Route the next handoff to the next owner.

### 3. Blockers Must Escalate Fast

Every blocker must include:

- Exact blocker
- What was tried
- Missing input
- Next owner
- Fallback path if available

### 4. Handoffs Must Be Actionable

Every handoff must include:

- Task
- Why now
- Exact target
- Inputs available
- Expected output
- Definition of done
- If blocked

### 5. Coding Claims Require Evidence

- No repo/path, no implementation claim.
- No changed files, diff, commit, PR, or test evidence, no code-complete claim.
- Specs and docs must be labeled as specs/docs, not implementation progress.

### 6. PM Is The Follow-Up Engine

PM must track owner, dependency, and stale status. During active projects, PM should check stale/warning/review-handoff states regularly and push the next concrete action.

### 7. Warnings Must Map To Action

- `blocked` -> PM follows up and helps clear the blocker.
- `stale`, `missing-next`, or `weak-output` -> PM asks the owner for a concrete update.
- Review queue -> Tech Lead reviews or routes required fixes.

## Healthy Workflow Example

1. User sends an objective.
2. `start-workflow.sh` sends it to PM and creates the workflow folder.
3. PM writes the plan and routes a handoff to Solution Designer.
4. Solution Designer writes the spec and routes implementation handoffs to Frontend and Backend.
5. Frontend and Backend implement their slices and route evidence to QA.
6. QA validates browser-facing flows with Playwright, routes bugs back to owners, or routes release evidence to Tech Lead.
7. Tech Lead approves, conditionally approves, or blocks release.
8. Tech Lead routes the final decision back to PM.

## Failure Modes To Avoid

- Delegating without enough input.
- Reporting "working" for too long with no meaningful output.
- Blocking without an owner or fallback.
- QA waiting until the whole system is complete before testing anything.
- QA approving browser-facing work without Playwright evidence or a documented Tech Lead exception.
- Requiring the user to manually chase every role.
- Tech Lead review becoming a bottleneck.
- Fan-out to every role at once without a concrete dependency reason.
