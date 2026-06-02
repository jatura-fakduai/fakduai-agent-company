# Getting Started

## Prerequisites
- OpenClaw installed (`npm i -g openclaw`)
- Python 3 for the dashboard server

## Quick Start

### 1. Choose a Preset
```bash
cp presets/tech-startup.json config/office.json
# or
cp presets/digital-agency.json config/office.json
# or
cp presets/hotel.json config/office.json
```

### 2. Bootstrap Workspaces
```bash
./scripts/bootstrap.sh
```

The script creates:
- One workspace per agent
- Initial shared `STATUS.md` files
- Dashboard data

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

### 4. Add Agents to OpenClaw
Merge the generated config from `generated/openclaw-agents.json` into `~/.openclaw/openclaw.json`, then restart the gateway:

```bash
openclaw gateway restart
```

The generated snippet includes the company agents, `tools.sessions.visibility = "all"`, and `tools.agentToAgent.allow` for `main` plus every configured company agent.

### 5. Start a Routed Workflow
```bash
./scripts/start-workflow.sh "Build the customer login flow"
```

This sends the objective to PM and creates a shared workflow folder under `~/.openclaw/shared/company-workflows/`.

Workflow starts, routed handoffs, and queued agent messages appear in the dashboard Work modal under the Activity tab.

### 6. Route a Handoff Manually
```bash
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff body>"
```

### 7. Auto-refresh Dashboard
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
