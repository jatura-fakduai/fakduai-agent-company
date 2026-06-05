# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

OpenClaw Company is a configurable AI office dashboard. It creates a Gather Town-style 2D office where multiple AI agents (running via the OpenClaw CLI framework) appear as animated avatars. The dashboard reflects real-time agent status parsed from `STATUS.md` files.

There is no package manager or build system. The stack is Bash + Python 3 + plain HTML5 Canvas — no npm, no pip, no compiled output.

## Key Commands

```bash
# 1. Review config and bootstrap agent workspaces
$EDITOR config/office.json
./scripts/bootstrap.sh

# 2. (Re)generate dashboard data from STATUS.md files
bash scripts/generate-dashboard.sh

# 3. Serve the dashboard (http://localhost:8090)
./scripts/open-dashboard.sh

# 4. Auto-regenerate dashboard every N seconds (background watcher)
./scripts/auto-refresh.sh 3        # every 3 seconds
./scripts/watch-dashboard.sh       # default 5s interval

# 5. Send a task to an agent
./scripts/send-task.sh <agent-id> "message"
```

## Architecture

### Data flow

```
config/office.json  +  ~/.openclaw/shared/agents/<id>/STATUS.md
        │
        ▼
scripts/generate-dashboard.sh   (Bash + Python)
        │
        ├── ui/dashboard/data/agents.json   (avatar positions, status)
        └── ui/dashboard/data/kanban.json   (task cards by stage)
                │
                ▼
        ui/dashboard/index.html             (Canvas polls these files every ~5s)
```

### Agent workspaces (outside the repo)

`bootstrap.sh` creates `~/.openclaw/workspace-<agent-id>/` for each agent defined in `config/office.json`. It copies the role-specific `AGENTS.md` when present and falls back to `templates/workspaces/default/` for shared files. Each workspace contains:
- `SOUL.md` — personality/rules
- `AGENTS.md` — role & scope
- `IDENTITY.md` — name/role/emoji
- `TOOLS.md` — environment notes

Shared status is written to `~/.openclaw/shared/agents/<id>/STATUS.md` by running agents and read by `generate-dashboard.sh`.

### Configuration

- **`config/office.json`** — active config (agents array, rooms grid, agentHomes positions, theme)
- **`scripts/sync-openclaw-config.sh`** — OpenClaw integration sync; merges agents into `~/.openclaw/openclaw.json`

### Dashboard UI (`ui/dashboard/index.html`)

Single HTML file with no dependencies. Uses Canvas 2D to draw the office floor plan, animated agent avatars (hair styles, colors, accessories), speech bubbles, and a minimap. A sidebar shows agent cards; a Kanban modal (TODO → DOING → TEST → DONE → BLOCKED) auto-generates from `kanban.json`.

## STATUS.md Format

Agents (and manual editors) must write `STATUS.md` in this structure for the dashboard parser to pick up fields correctly:

```markdown
# STATUS.md
- refreshed_at: <ISO timestamp>
- agent_id: <id>
- current objective: <task>
- current status: idle | working | blocked | offline
- active blocker: <issue or "none">
- next action: <what's next>
- last meaningful output: <summary>

## Implementation Plan
(optional — content becomes kanban cards)

## Collaboration
(optional — who needs help from whom)
```

`generate-dashboard.sh` parses these files with Python regex; field names must match exactly.

## Environment Variables (used by scripts)

| Variable | Default | Purpose |
|---|---|---|
| `CONFIG` | `$REPO_ROOT/config/office.json` | Active office config |
| `SHARED_ROOT` | `~/.openclaw/shared/agents` | Where STATUS.md files live |
| `WORKSPACE_ROOT` | `~/.openclaw` | Agent workspace parent dir |
| `PORT` | `8090` | Dashboard HTTP server port |
| `INTERVAL` | `5` | Auto-refresh seconds |

## Important Behaviors

- `ui/dashboard/data/` is **git-ignored** — `agents.json` and `kanban.json` are always regenerated at runtime.
- Agent workspaces are created **outside the repo** in `~/.openclaw/`; `bootstrap.sh` is safe to re-run (it skips existing workspaces).
- OpenClaw CLI (`npm i -g openclaw`) is an **optional** dependency — the dashboard works in read-only mode without it.
- Python 3 must be available on `$PATH` for `generate-dashboard.sh` and the HTTP server.
