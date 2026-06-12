# Actionable Handoff Template

Use this template whenever work moves between roles. A handoff should let the receiving agent start immediately without guessing.

This template follows the mandatory [Agent Execution Control Policy](execution-control-policy.md). Handoffs missing output, evidence, stale timeout, or next route should be treated as incomplete.

## Communication Flow

```text
PM -> Solution Designer -> Frontend + Backend -> QA -> Tech Lead -> Deploy
```

This is the main sequence only. Agents may communicate across steps when that removes delay.
When a handoff targets multiple roles, route no more than the configured company concurrency allows. The default is `COMPANY_MAX_PARALLEL=2`; use `COMPANY_MAX_PARALLEL=1` on small hosts.

Routing status must follow delivery states from `execution-control-policy.md`.
`route-handoff.sh` records `delivering` / `delivered_waiting_for_receiver`; the receiving agent must update to `working` only after it has started a concrete action and can cite first evidence. A dashboard showing `delivered_waiting_for_receiver` for more than 5 minutes should be treated as stale acknowledgement, not real progress.

## Required Format

```md
# HANDOFF

## Task
<What needs to be done>

## Output
- <Exact file path / endpoint / UI surface / test / report expected>

## Scope
- <What is included>

## Non-goals
- <What is excluded>

## Definition of Done
- <Conditions that make this handoff complete>

## Evidence Required
- <Commands, logs, screenshots, artifact paths, API responses, test results>

## Stale Timeout
- <10/15/20/30 minutes>

## Next Route
- <Next owner and what they should receive>
```

## Routing Command

```bash
./scripts/route-handoff.sh <from-agent> <to-agent> <workflow-id> "<handoff body>"
```

For larger handoffs:

```bash
cat handoff.md | ./scripts/route-handoff.sh designer frontend <workflow-id>
```

## Examples

### PM -> Solution Designer

```md
# HANDOFF

## Task
Design the customer login flow for the web app.

## Why Now
Users must authenticate before using the product. Developers need a build-ready spec before implementation starts.

## Exact Target
- Web app login page and post-login redirect
- Environment: development branch

## Inputs Available
- Requirement: email and password login
- Must support role-based redirects: admin -> dashboard, user -> home

## Expected Output
- User journey
- UI states
- API contract
- Frontend and backend implementation handoffs

## Definition of Done
Developers can start without guessing behavior or contracts.

## If Blocked
- Ask PM for missing scope.
- Escalation owner: PM
```

### Solution Designer -> Frontend + Backend

```md
# HANDOFF

## Task
Implement the login flow according to the approved spec.

## Why Now
The spec is ready and both implementation slices can start under the company concurrency limit.

## Exact Target
- Frontend: login page UI, form validation, token storage
- Backend: POST /api/auth/login, token generation, role-based response

## Inputs Available
- User journey from Solution Designer
- API request/response contract
- UI wireframe and error states

## Expected Output
- Frontend: changed files, tests, and screenshot/manual evidence
- Backend: changed files, tests, and API verification evidence
- QA: Playwright validation for browser-facing critical paths

## Definition of Done
Both implementation owners route evidence to QA.

## If Blocked
- Contract mismatch -> Solution Designer
- Technical feasibility issue -> Tech Lead
- Escalation owner: PM
```

### QA -> Frontend/Backend Bug

```md
# HANDOFF

## Task
Fix login redirect bug after successful token response.

## Why Now
QA found that successful login redirects to the wrong page.

## Exact Target
- Frontend: redirect logic after login success
- Backend: POST /api/auth/login response if role field is incorrect

## Inputs Available
- QA report with expected vs actual behavior
- Screenshot after login
- Network response log

## Expected Output
- Fix commit or changed files
- Verification evidence
- Route back to QA for retest

## Definition of Done
QA retest passes.

## If Blocked
- If ownership is unclear, route to Tech Lead.
- Escalation owner: PM
```

### QA -> Tech Lead

```md
# HANDOFF

## Task
Review and approve the login feature for release.

## Why Now
QA validation passed and release approval is the next gate.

## Exact Target
- Frontend login implementation
- Backend auth endpoint

## Inputs Available
- QA report
- Playwright report/trace/screenshot/video paths when applicable
- Test output
- Changed files or PR links

## Expected Output
- Tech Lead decision: approve, approve with conditions, or block

## Definition of Done
Tech Lead routes final decision to PM.

## If Blocked
- Architecture issue -> Solution Designer
- Scope issue -> PM
```

## Rules

- Do not send vague handoffs like "please check this" without target and expected output.
- If repo/path/access is not usable, say so in `If Blocked`.
- Implementation handoffs must require evidence.
- QA and review handoffs must include concrete pass/fail criteria.
- Browser-facing release handoffs must include Playwright evidence unless Tech Lead documents an exception.
- Progress and stale decisions must follow `docs/agent-workflows/execution-control-policy.md`.
- Do not treat a routed handoff as `working` until the receiver has written an evidence-based status update.
- Empty delivery logs or logs containing only the initial send line are delivery/control-plane failures and should trigger retry or reassignment.
