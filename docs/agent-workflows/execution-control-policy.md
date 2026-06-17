# Agent Execution Control Policy

This is the default execution-control policy for routed company-agent work. It exists to prevent long-running work from becoming silent, ambiguous, or falsely reported as progress.

## Objective
Every agent must report progress from evidence, not intent. Every handoff must define the expected output before work starts.

## Required Handoff Fields
Every handoff must include:

- Task: one concrete action for the receiving role.
- Output: exact file path, endpoint, UI page, test, report, screenshot, or artifact expected.
- Scope: what is included.
- Non-goals: what must not be changed or evaluated.
- Definition of Done: objective pass criteria.
- Evidence Required: commands, logs, screenshots, artifact paths, API responses, test results, commits, or diffs.
- Stale Timeout: max time allowed in `working` without new evidence.
- Next Route: who receives the work after completion.

## Required Status Fields
Each agent `STATUS.md` must be evidence-based:

- current objective: the specific deliverable being produced.
- current status: `working`, `blocked`, `waiting`, `passed`, `failed`, or `done`, plus percent when PM requests progress.
- active blocker: owner, missing input, and next action. Use `none` only when no blocker exists.
- next action: one concrete next step.
- last meaningful output: latest artifact, commit, diff, test result, log, screenshot, API response, or route path.
- workflow id: current workflow when applicable.

Do not use bare `working` as a meaningful update.

## Delivery State Rule
Routing a handoff is not proof that the receiving agent has started work.

Allowed delivery/status progression:

- `queued`: handoff exists but delivery has not started.
- `delivering`: delivery process is running.
- `delivered_waiting_for_receiver`: delivery completed; receiver has not yet acknowledged with evidence.
- `working`: receiver has read the handoff and has started a concrete action with first evidence or a precise next command.
- `blocked`: receiver cannot proceed and names owner, missing input, and next action.
- `done` / `passed` / `failed`: receiver produced evidence.
- `delivery_failed`: delivery failed or timed out before receiver acknowledgement.

`route-handoff.sh` must not set a receiver to `working`. Only the receiving agent may set `working`, and only after writing a meaningful `last meaningful output`.

If `delivered_waiting_for_receiver` remains unchanged for more than 5 minutes, PM/monitoring should treat it as stale delivery acknowledgement and retry or reassign.

## Progress Percent Rule
Progress may advance only when evidence exists:

- 0-10%: scope accepted, owner assigned, handoff created.
- 10-35%: design, backend contract, or implementation evidence exists.
- 35-60%: frontend or integration evidence exists.
- 60-80%: QA evidence exists.
- 80-90%: Tech Lead review evidence exists.
- 90-100%: deploy, smoke, or user-facing verification evidence exists.

If evidence is absent, percent must not move even if an agent says they are working.

## Stale Work Rule
Default stale timeout:

- Planning/design: 15 minutes without artifact or explicit blocker.
- Implementation: 20 minutes without diff, commit, test log, or explicit blocker.
- QA/review: 15 minutes without test evidence, defect report, review artifact, or explicit blocker.
- Deploy/smoke: 10 minutes without command/log evidence or explicit blocker.

When stale:

- First stale event: PM sends a narrow corrective handoff with exact output and a 10-15 minute timeout.
- Second stale event: PM escalates to Tech Lead or reassigns/splits the task.
- Third stale event: PM marks the phase blocked, reports owner/missing evidence to the user, and stops claiming progress.

If an agent is stale because the delivery log is empty or only contains the initial send line, treat it as a delivery/control-plane failure, not as productive agent work.

## Token Control Rule
PM should not repeatedly read full logs, large artifacts, screenshots, or source files during periodic monitoring. Periodic reports should read compact status and event summaries first, then inspect large evidence only when a status changes, a blocker appears, or a user asks for details.

Long-running monitoring should use the PM-owned monitor utility or cron with compact prompts. PM should receive decision-ready summaries rather than polling every role's raw logs.

## Periodic Report Format
When the user asks for periodic reports, each report must include:

- Percent complete.
- Current owner.
- Latest evidence path or log.
- Blocker, if any.
- Next action and timeout.

Example:

```text
Progress 35%.
Owner: Backend.
Evidence: frontend diff exists in public/trading.js; backend artifact is missing.
Blocker: backend endpoint/test evidence absent.
Next: backend must deliver /api/example + test evidence within 20m, otherwise PM escalates.
```

## Standard Handoff Template

```markdown
# HANDOFF

## Task
[One concrete action.]

## Output
- [Exact file path / endpoint / UI surface / test / report.]

## Scope
- [Included.]

## Non-goals
- [Excluded.]

## Definition of Done
- [Objective pass criteria.]

## Evidence Required
- [Artifact paths, commands, test logs, screenshots, API responses.]

## Stale Timeout
- [10/15/20/30 minutes.]

## Next Route
- [Next owner and what they should receive.]
```

## Role-Specific Expectations

- PM: enforce output, evidence, stale timeout, and escalation. Do not let `working` hide missing evidence.
- Solution Designer: produce build-ready artifacts with file targets, contracts, risks, and verification points.
- Backend: include changed files, endpoint/data contract, tests, migrations, security boundaries, and artifact path.
- Frontend: include changed files, UI states, API integration evidence, screenshots/browser evidence where relevant, and artifact path.
- QA: include pass/fail result, commands, Playwright evidence for browser-facing work, screenshots/traces when available, and residual risk.
- Tech Lead: include decision, findings by severity, evidence reviewed, required fixes, and release risk.

## Anti-Patterns

- Bare `working` status with no meaningful output.
- Handoff without output path, Definition of Done, Evidence Required, or Next Route.
- Progress percentage based on effort, not evidence.
- Blocker without owner, missing input, and next action.
- QA pass for browser-facing work without Playwright evidence or documented Tech Lead exception.
- Deploy or release approval without the relevant QA and Tech Lead evidence.
