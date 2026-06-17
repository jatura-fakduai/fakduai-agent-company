# OpenClaw Company - Configurable AI Office Dashboard

Create a multi-agent company workspace on OpenClaw with a lightweight office dashboard and role-based agent workflows.

Customize the active team by editing a single office config.

## Quick Start

```bash
# Review or edit the active six-agent company config
$EDITOR config/office.json

# Create workspaces, shared status files, dashboard data,
# and merge company agents into ~/.openclaw/openclaw.json
./scripts/bootstrap.sh

# Restart/recreate the OpenClaw gateway or container so it loads the new agents

# Run the dashboard
./scripts/dashboard.sh

# Start a routed multi-agent workflow
./scripts/start-workflow.sh "Build the customer login flow"
```

## Structure

```
├── config/office.json          # office config (agents, rooms, homes)
├── templates/                  # workspace templates
├── scripts/                    # bootstrap, dashboard, task scripts
├── ui/dashboard/               # office-style dashboard
├── shared/                     # shared data between agents
└── docs/                       # คู่มือ
```

## Routed Agent Workflow

The primary delivery sequence is:

```text
PM -> Solution Designer -> Frontend + Backend -> QA -> Tech Lead
```

Agent sends are throttled by default with `COMPANY_MAX_PARALLEL=2` so a routed workflow cannot launch every role at once and peg local CPU. Use `COMPANY_MAX_PARALLEL=1` on smaller hosts.

Start with:

```bash
./scripts/start-workflow.sh "Build the customer login flow"
```

Agents can pass work to each other with:

```bash
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff body>"
```

`bootstrap.sh` runs `scripts/sync-openclaw-config.sh` automatically. Re-run that sync script after changing `config/office.json`; it updates OpenClaw config by agent id, backs up the previous config, enables agent-to-agent routing, syncs auth profiles from `main`, and validates the result.

See [Automatic Routing](docs/agent-workflows/automatic-routing.md) for the full workflow.

All routed work must follow the [Agent Execution Control Policy](docs/agent-workflows/execution-control-policy.md): every handoff needs explicit output, definition of done, required evidence, stale timeout, and next route. Progress percentages are evidence-based, and bare `working` status is not accepted as progress.

Routing a handoff does not count as active work. `route-handoff.sh` records delivery states (`delivering`, then `delivered_waiting_for_receiver`) and the receiving agent must write its own evidence-based `working` status. Empty delivery logs or missing receiver acknowledgement should be treated as delivery/control-plane failures, not progress.

PM can run the [workflow monitor utility](docs/agent-workflows/ops-monitor.md) for compact stale/delivery checks instead of polling large logs:

```bash
./scripts/monitor-workflows.sh
./scripts/monitor-workflows.sh --apply
```

QA must use Playwright for browser-facing UI/E2E validation. See [Playwright QA Policy](docs/agent-workflows/playwright-qa-policy.md).

`scripts/dashboard.sh` keeps dashboard data refreshed every 3 seconds by default. The Work modal includes an Activity tab that shows workflow starts, handoffs, and queued agent messages.

## Docs

- [Getting Started](docs/getting-started.md)
- [Adding Roles](docs/adding-roles.md)
- [Workflow Monitor Utility](docs/agent-workflows/ops-monitor.md)
