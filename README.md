# OpenClaw Company - Configurable AI Office Dashboard

Create a multi-agent company workspace on OpenClaw with a lightweight office dashboard and role-based agent workflows.

Use a preset or customize your own team by editing a single office config.

## Quick Start

```bash
# Choose a preset, or create your own config
cp presets/tech-startup.json config/office.json

# Create workspaces, shared status files, and dashboard data
./scripts/bootstrap.sh

# Merge generated/openclaw-agents.json into ~/.openclaw/openclaw.json,
# then restart OpenClaw gateway

# Run the dashboard
./scripts/dashboard.sh

# Start a routed multi-agent workflow
./scripts/start-workflow.sh "Build the customer login flow"
```

## Structure

```
├── config/office.json          # office config (agents, rooms, homes)
├── presets/                    # ready-made presets
│   ├── tech-startup.json
│   ├── digital-agency.json
│   └── hotel.json
├── templates/                  # workspace templates + openclaw config
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

Start with:

```bash
./scripts/start-workflow.sh "Build the customer login flow"
```

Agents can pass work to each other with:

```bash
./scripts/route-handoff.sh pm designer <workflow-id> "<handoff body>"
```

See [Automatic Routing](docs/agent-workflows/automatic-routing.md) for the full workflow.

QA must use Playwright for browser-facing UI/E2E validation. See [Playwright QA Policy](docs/agent-workflows/playwright-qa-policy.md).

`scripts/dashboard.sh` keeps dashboard data refreshed every 3 seconds by default. The Work modal includes an Activity tab that shows workflow starts, handoffs, and queued agent messages.

## Presets

- **Tech Startup** - CEO, CTO, Tech Lead, Frontend, Backend, PM, Designer
- **Digital Agency** - Creative Director, Art Director, Copywriter, Media Planner, Account Manager, Social Manager
- **Hotel** - General Manager, Front Desk, F&B Manager, Housekeeping Lead, Events Coordinator, Guest Relations

## Docs

- [Getting Started](docs/getting-started.md)
- [Adding Roles](docs/adding-roles.md)
- [Presets Guide](docs/presets.md)
