# Agent Operating Rules

These rules help agents collaborate quickly, hand off work cleanly, and avoid silent blockers.

For the canonical evidence, progress, and stale-timeout rules, see [Agent Execution Control Policy](execution-control-policy.md). These rules are mandatory for routed workflow handoffs and role `STATUS.md` updates.

## Communication Flow

```text
PM -> Solution Designer -> Frontend + Backend -> QA -> Tech Lead -> Deploy
```

This is the main sequence. Agents may communicate across steps when that removes delay:

- QA finds a bug -> route it directly to the suspected implementation owner.
- Dev is blocked -> route a focused question to Solution Designer or Tech Lead.
- Any unresolved blocker -> escalate to PM.

Parallel routing must respect the company send throttle. Default to at most two active role-agent sends (`COMPANY_MAX_PARALLEL=2`), and prefer one on constrained hosts.

## 1. Shared Contract, Different Specialties

All roles share the same collaboration rules:

- Handoff format
- Status reporting
- Escalation rules
- Definition of done
- Evidence expectations

Each role adds its own specialty depth and artifacts.

## 2. One Owner Per Failure Mode

- PM: stale work, missing next action, weak output, delayed handoff, unresolved escalation.
- Solution Designer: requirement ambiguity, design gaps, missing contracts.
- Tech Lead: review gate, architecture decisions, implementation routing for hard trade-offs.
- QA: verification quality, Playwright-backed browser validation, reproduction quality, evidence quality.
- Frontend/Backend: implementation quality, changed files, diff, test evidence.

## 3. Standard Handoff Format

Every handoff must include:

- Task
- Output
- Scope
- Non-goals
- Definition of done
- Evidence required
- Stale timeout
- Next route

Do not route vague requests like "please check this" without target and expected output.

## 4. Evidence Rules

- No repo/path, no implementation claim.
- No changed files, diff, commit, PR, or test evidence, no code-complete claim.
- Specs and docs must be labeled as specs/docs, not implementation progress.

## 5. Blocked Fallback Rule

Blocked is acceptable. Silent blocking is not.

When blocked, report:

- Exact blocker
- What was tried
- Missing input
- Owner of the next unblock step
- Fallback path if available

## 6. STATUS Discipline

After meaningful work, update `STATUS.md` with:

- Current Objective
- Status
- Next Action
- Last Meaningful Output
- Collaboration

Dashboard movement is inferred from status and routing events. Agents should not attach, describe, or generate desk/screen/monitor SVG assets when they move to Talk or join a discussion; those visual assets are owned by the dashboard and remain desk-only decoration.

## 7. When To Ask vs When To Act

Act when:

- The target is clear.
- Inputs are usable.
- Risk is low.
- The task is inside your role.

Ask or escalate when:

- The target is unclear.
- Access does not work.
- A cross-role dependency is unusable.
- A trade-off affects multiple teams.

## 8. Definition Of Done

Work is done when:

- Output matches expected output.
- Role-specific artifacts are complete.
- The next owner can continue without guessing.
- Evidence is attached.
- `STATUS.md` is updated.

## 9. Lightweight Event Mindset

Think in workflow events:

```text
started -> blocked -> handoff sent -> artifact saved -> review requested -> done
```

## 10. Healthy Sequence

1. PM receives the objective.
2. PM scopes the work and routes it to Solution Designer.
3. Solution Designer creates the spec and routes it to implementation owners.
4. Frontend and Backend implement and route evidence to QA.
5. QA runs Playwright for browser-facing flows, routes bugs, or routes release evidence to Tech Lead.
6. Tech Lead reviews, approves, or routes required fixes.
7. PM receives the final completion summary.

## 11. Anti-Patterns

- "Working" for too long with no new output.
- Blocked status without the next owner.
- Handoff without repo/path/expected output.
- Reporting done without an artifact.
- QA approving browser-facing work without Playwright evidence or a documented Tech Lead exception.
- Role overlap where everyone waits for someone else.
- Tech Lead review becoming a bottleneck.
- Fan-out to every role at once without dependency or capacity control.
