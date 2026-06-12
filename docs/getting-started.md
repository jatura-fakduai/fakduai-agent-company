# Getting Started

## Prerequisites
- OpenClaw installed (`npm i -g openclaw`)
- Python 3 for the dashboard server

## Quick Start

### 1. Review the Active Company Config
```bash
$EDITOR config/office.json
```

### 2. Bootstrap Workspaces
```bash
./scripts/bootstrap.sh
```

The script creates:
- One workspace per agent
- Initial shared `STATUS.md` files
- Dashboard data
- OpenClaw agent entries and agent-to-agent routing in `~/.openclaw/openclaw.json`

`bootstrap.sh` also runs:

```bash
./scripts/sync-openclaw-config.sh
```

The sync is safe to run again after editing `config/office.json`: it merges agents by id, backs up the previous OpenClaw config, enables `tools.sessions.visibility = "all"`, enables `tools.agentToAgent`, syncs auth/model profiles from `main`, and validates the config.

### 3. Open the Dashboard
```bash
./scripts/dashboard.sh
# open http://127.0.0.1:8090
```

By default this also refreshes dashboard data every 3 seconds.

Useful options:

```bash
./scripts/dashboard.sh --port 8091
./scripts/dashboard.sh --interval 5
./scripts/dashboard.sh --once
./scripts/dashboard.sh --no-refresh
```

### 4. Restart OpenClaw Gateway
Restart or recreate the OpenClaw gateway/container so the running process loads the updated agent list:

```bash
openclaw gateway restart
```

If your gateway is running inside Docker/Compose and `openclaw gateway restart` reports that the service is disabled, restart the OpenClaw container from your host instead.

If you want to review the generated config manually, run bootstrap with:

```bash
SKIP_OPENCLAW_SYNC=1 ./scripts/bootstrap.sh
```

Then inspect `generated/openclaw-agents.json` and run `./scripts/sync-openclaw-config.sh` when ready.

### 5. Start a Routed Workflow
```bash
./scripts/start-workflow.sh "Build the customer login flow"
```

This sends the objective to PM and creates a shared workflow folder under `~/.openclaw/shared/company-workflows/`.

Workflow starts, routed handoffs, and queued agent messages appear in the dashboard Work modal under the Activity tab.

Company agent sends are throttled by default so a PM fan-out cannot start every role at once and saturate CPU:

```bash
COMPANY_MAX_PARALLEL=2 ./scripts/start-workflow.sh "Build the customer login flow"
```

Set `COMPANY_MAX_PARALLEL=1` for low-resource hosts, or `0` to disable the guard.

### 6. Route a Handoff Manually
```bash
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff body>"
```

Detached delivery remains enabled by default, but `scripts/send-task.sh` enforces the shared concurrency slots.

After routing, check delivery/control-plane health without reading large logs:

```bash
./scripts/monitor-workflows.sh --workflow <workflow-id>
```

Apply stale delivery markers when needed:

```bash
./scripts/monitor-workflows.sh --workflow <workflow-id> --apply
```

### 7. Post-clone Smoke
Run these after a fresh clone/bootstrap:

```bash
bash -n scripts/*.sh
DASHBOARD_DATA_DIR=/tmp/openclaw-dashboard-smoke bash scripts/generate-dashboard.sh
./scripts/monitor-workflows.sh
```

`route-handoff.sh` should set receivers to `delivering` / `delivered_waiting_for_receiver`, not `working`. `working` is reserved for the receiver's own evidence-based acknowledgement.

### 8. Auto-refresh Dashboard
```bash
./scripts/auto-refresh.sh 3
```

## Customization
Edit `config/office.json` to change:
- Office name
- Agent count and names
- Rooms and layout
- Avatar colors
- Hair style (`short`, `messy`, `ponytail`, `neat`, `bun`, `cap`)

## Send Ad-Hoc Agent Tasks
```bash
./scripts/send-task.sh pm "Draft a release plan for the login flow"
```

## QA Browser Validation

QA must use Playwright for browser-facing UI/E2E validation. See [Playwright QA Policy](agent-workflows/playwright-qa-policy.md).
