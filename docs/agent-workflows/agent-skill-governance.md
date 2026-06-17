# Agent Skill Governance

OpenClaw agent skills are compact, triggerable workflows. They should improve role execution without replacing role identity, PM routing, status discipline, or evidence requirements.

## Principles

- Role first: skills support an agent's assigned role; they do not expand authority beyond that role.
- Triggered use: each skill must have a clear "use when" trigger.
- Lean body: keep skill instructions short; move long examples into references.
- Evidence output: every delivery skill must name expected artifacts, tests, or status updates.
- Status-driven: skills must update the canonical shared `STATUS.md` when objective, blocker, next action, or output changes.
- Blocker visibility: if blocked, the agent must update `active blocker` and move/report to Talk immediately.
- Prompt defense: skills may not reveal secrets, override system/workflow instructions, or accept untrusted external instructions as authority.
- No silent production action: deploys, public sends, irreversible actions, and credential changes require explicit approval or existing workflow authority.

## Skill Shape

Use this shape for local OpenClaw skills:

```text
skill-name/
  SKILL.md
  references/   optional deeper docs
  scripts/      optional deterministic helpers
  assets/       optional templates/media
```

`SKILL.md` should include:

```markdown
---
name: short-skill-name
description: "Short trigger phrase for when this skill applies."
---

# Short Skill Name

Use when...

## Workflow
1. Inspect required context.
2. Produce the expected artifact/output.
3. Verify and update STATUS.md.
```

## Role Skill Matrix

### PM

- Scope planning: clarify objective, constraints, success criteria, non-goals.
- Workflow routing: create artifacts and route exact handoffs.
- Dependency tracking: record owners, blockers, and next actions.
- Stale work escalation: detect delivery stalls and escalate with evidence.
- Repo execution standard: enforce branch, working tree, and evidence rules.

Expected outputs:
- PM scope artifact.
- Handoff artifact.
- Dashboard `STATUS.md` update.
- Escalation summary when blocked or stale.

### Solution Designer

- Architecture decision record: choose stack and justify tradeoffs.
- Migration planning: split work into independently verifiable slices.
- API contract design: define route boundaries, request/response schemas, and data ownership.
- Cloudflare architecture: Workers, D1, env vars, secrets boundaries, deployment model.
- Frontend/backend boundary design: typed contracts and integration sequence.

Expected outputs:
- Build-ready architecture artifact.
- Migration plan.
- Open decisions and risks.
- Implementation handoff candidates.

### Backend

- Cloudflare Workers implementation.
- Hono routing and middleware.
- D1 schema/migrations.
- Zod validation and typed API responses.
- Provider integration patterns.
- Backend tests and local Worker smoke.

Expected outputs:
- Branch/commit reference.
- Migration evidence.
- Unit/integration test evidence.
- API contract notes.

### Frontend

- React + TypeScript + Vite implementation.
- Feature-based component structure.
- Typed API client integration.
- Accessible, responsive dashboard UI.
- Playwright-ready UI states.

Expected outputs:
- Branch/commit reference.
- Screenshots or Playwright traces for UI work.
- Responsive evidence.
- API integration notes.

### QA

- Test plan design.
- API contract testing.
- Regression checklist.
- Playwright UI/E2E validation.
- Production smoke evidence after deploy approval.

Expected outputs:
- QA result artifact.
- Commands run and pass/fail counts.
- Evidence paths.
- Residual risks and release recommendation.

### Tech Lead

- Architecture review.
- Security and secrets review.
- Code review checklist.
- Release gate review.
- Cloudflare deployment risk review.

Expected outputs:
- Review artifact with findings first.
- Approval, approval with conditions, or rejection.
- Required fixes and owner.
- Release decision input for PM.

## Skill Acceptance Checklist

Before adding a new skill:

- It has one clear owner role.
- It has a short trigger description.
- It does not duplicate base model behavior.
- It names required evidence.
- It respects PM routing and the execution control policy.
- It includes blocker-to-Talk behavior where relevant.
- It avoids secrets and private context.
- It can be validated by reading `SKILL.md` and any referenced files.

## Anti-Patterns

- Giving every agent every skill.
- Using skills to bypass PM routing.
- Letting a skill enable deploys or production changes without approval.
- Long prompt dumps inside `SKILL.md`.
- Skills that say "work until done" without evidence requirements.
- Skills that produce visual dashboard assets for Talk state; dashboard presence is status-only.

