#!/usr/bin/env bash
set -euo pipefail

# Generate agents.json for dashboard from config + STATUS.md files
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="${CONFIG:-$REPO_ROOT/config/office.json}"

# Resolve an OpenClaw state root that exists in the current runtime. This keeps
# stale host paths from poisoning dashboard data after clone/restart.
DEFAULT_OPENCLAW_HOME="$HOME/.openclaw"
for candidate in \
  "${OPENCLAW_STATE_DIR:-}" \
  "${WORKSPACE_ROOT:-}" \
  "$HOME/.openclaw" \
  "/home/node/.openclaw" \
  "/data/.openclaw"; do
  if [ -n "$candidate" ] && [ -d "$candidate/shared/agents" ]; then
    DEFAULT_OPENCLAW_HOME="$candidate"
    break
  fi
done

SHARED_ROOT="${SHARED_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/agents}"
WORKFLOW_ROOT="${WORKFLOW_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-workflows}"
OUTBOX_ROOT="${OUTBOX_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-outbox}"
ACTIVITY_ROOT="${ACTIVITY_ROOT:-$DEFAULT_OPENCLAW_HOME/shared/company-activity}"

# If explicit roots are stale, fall back to the resolved runtime root.
if [ ! -d "$SHARED_ROOT" ]; then
  SHARED_ROOT="$DEFAULT_OPENCLAW_HOME/shared/agents"
fi
if [ ! -d "$WORKFLOW_ROOT" ]; then
  WORKFLOW_ROOT="$DEFAULT_OPENCLAW_HOME/shared/company-workflows"
fi
if [ ! -d "$OUTBOX_ROOT" ]; then
  OUTBOX_ROOT="$DEFAULT_OPENCLAW_HOME/shared/company-outbox"
fi
if [ ! -d "$ACTIVITY_ROOT" ]; then
  ACTIVITY_ROOT="$DEFAULT_OPENCLAW_HOME/shared/company-activity"
fi
export OPENCLAW_STATE_DIR="$DEFAULT_OPENCLAW_HOME" WORKFLOW_ROOT OUTBOX_ROOT ACTIVITY_ROOT
OUT_DIR="${DASHBOARD_DATA_DIR:-$REPO_ROOT/ui/dashboard/data}"
OUT_FILE="$OUT_DIR/agents.json"
SCREEN_DIR="$OUT_DIR/screenshots"

mkdir -p "$OUT_DIR" "$SCREEN_DIR"

python3 - "$CONFIG" "$SHARED_ROOT" "$OUT_FILE" "$SCREEN_DIR" <<'PY'
import datetime
import json, os, re, sys, mimetypes

import shutil
from pathlib import Path

config_path, shared_root, out_file, screen_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
out_dir = str(Path(out_file).parent)
state_root = Path(os.environ.get('OPENCLAW_STATE_DIR', str(Path.home() / '.openclaw')))
if not Path(shared_root).is_dir():
    shared_root = str(state_root / 'shared' / 'agents')
if not Path(os.environ.get('WORKFLOW_ROOT', '')).is_dir():
    os.environ['WORKFLOW_ROOT'] = str(state_root / 'shared' / 'company-workflows')
if not Path(os.environ.get('OUTBOX_ROOT', '')).is_dir():
    os.environ['OUTBOX_ROOT'] = str(state_root / 'shared' / 'company-outbox')
if not Path(os.environ.get('ACTIVITY_ROOT', '')).is_dir():
    os.environ['ACTIVITY_ROOT'] = str(state_root / 'shared' / 'company-activity')
config = json.load(open(config_path))
agents_config = {a['id']: a for a in config.get('agents', [])}
rooms = config.get('rooms', [])
agent_homes = config.get('agentHomes', {})

def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)

def iso_utc(dt):
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')

def mtime_iso(path):
    return iso_utc(datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc))

def path_mtime_iso(path):
    return iso_utc(datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc))

def now_iso():
    return iso_utc(utc_now())

generated_at = now_iso()

def generated_meta(source_status='ok', warnings=None, **extra):
    meta = {
        'generatedAt': generated_at or now_iso(),
        'sourceStatus': source_status,
        'sourceRoots': {
            'sharedAgents': shared_root,
            'workflows': os.environ.get('WORKFLOW_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-workflows')),
            'outbox': os.environ.get('OUTBOX_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-outbox')),
            'activity': os.environ.get('ACTIVITY_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-activity')),
        },
        'warnings': warnings or [],
    }
    meta.update(extra)
    return meta

def parse_ts(value):
    if not value or value == 'never':
        return None
    try:
        normalized = value.replace('Z', '+00:00')
        return datetime.datetime.fromisoformat(normalized)
    except Exception:
        return None

TASK_TALK_SECONDS = int(os.environ.get('DASHBOARD_TASK_TALK_SECONDS', '180'))
activity_root = Path(os.environ.get('ACTIVITY_ROOT', str(state_root / 'shared' / 'company-activity')))

def task_event_preview(event):
    text = re.sub(r'\s+', ' ', event.get('summary', '') or '').strip()
    return text[:160] or f"Task sent to {event.get('to', 'agent')}"

def task_event_age_seconds(event):
    dt = parse_ts(event.get('ts', ''))
    if not dt:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return max(0, int((utc_now() - dt.astimezone(datetime.timezone.utc)).total_seconds()))

def is_recent_task_event(event):
    age = task_event_age_seconds(event)
    return age is not None and age <= TASK_TALK_SECONDS

def load_task_send_events():
    path = activity_root / 'task-sends.ndjson'
    if not path.exists():
        return []
    dedup = {}
    try:
        lines = path.read_text(encoding='utf-8', errors='ignore').splitlines()[-500:]
    except Exception:
        return []
    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except Exception:
            continue
        if not event.get('to'):
            continue
        event.setdefault('kind', 'task_sent')
        event.setdefault('type', 'task_sent')
        event.setdefault('from', 'human')
        event.setdefault('summary', task_event_preview(event))
        key = event.get('sendId') or f"{event.get('ts', '')}:{event.get('from', '')}:{event.get('to', '')}:{event.get('summary', '')}"
        prev = dedup.get(key)
        if not prev or (event.get('ts', '') >= prev.get('ts', '')):
            dedup[key] = event
    return sorted(dedup.values(), key=lambda e: e.get('ts', ''), reverse=True)

task_send_events = load_task_send_events()
latest_task_by_agent = {}
for event in task_send_events:
    target = event.get('to')
    if target and target not in latest_task_by_agent:
        latest_task_by_agent[target] = event

def stale_summary(updated, status):
    dt = parse_ts(updated)
    if not dt:
        return {'level': 'unknown', 'ageMinutes': None, 'reason': 'missing or invalid updatedAt'}
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    age_minutes = max(0, int((utc_now() - dt.astimezone(datetime.timezone.utc)).total_seconds() // 60))
    if status == 'blocked' and age_minutes >= 15:
        return {'level': 'stale', 'ageMinutes': age_minutes, 'reason': f'not refreshed for {age_minutes}m'}
    if status == 'working' and age_minutes >= 60:
        return {'level': 'stale', 'ageMinutes': age_minutes, 'reason': f'not refreshed for {age_minutes}m'}
    if status == 'working' and age_minutes >= 30:
        return {'level': 'aging', 'ageMinutes': age_minutes, 'reason': f'not refreshed for {age_minutes}m'}
    return {'level': 'fresh', 'ageMinutes': age_minutes, 'reason': ''}

def blocker_from_status(status, text, next_action=''):
    active = pick_field(text, 'active blocker', '') or pick_field(text, 'Active Blocker', '')
    blockers = parse_section(text, 'Blockers') if 'parse_section' in globals() else ''
    missing = active if active and active.lower() not in ('none', 'n/a', 'no') else blockers
    is_blocked = status == 'blocked' or bool(missing and missing.lower() not in ('none', 'n/a', 'no blockers'))
    return {
        'isBlocked': bool(is_blocked),
        'owner': pick_field(text, 'blocker owner', '') or pick_field(text, 'owner', ''),
        'missingInput': missing[:240] if missing else '',
        'nextAction': (next_action or pick_field(text, 'next action', '') or pick_field(text, 'Next Action', ''))[:240],
    }

def workspace_dir_for(slug):
    candidates = [
        Path(os.environ.get('OPENCLAW_STATE_DIR', '')) / f'workspace-{slug}' if os.environ.get('OPENCLAW_STATE_DIR') else None,
        Path('/home/node/.openclaw') / f'workspace-{slug}',
        Path.home() / '.openclaw' / f'workspace-{slug}',
        Path('/data/.openclaw') / f'workspace-{slug}',
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate
    return Path('/data/.openclaw') / f'workspace-{slug}'

def pick_field(text, field, fallback):
    # format: - current objective: foo
    for line in text.splitlines():
        m = re.match(r'-?\s*' + re.escape(field) + r'\s*:\s*(.+)', line.strip(), re.IGNORECASE)
        if m:
            return m.group(1).strip()

    # format: ## Current Objective\nfoo
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower() == f'## {field}'.lower():
            vals=[]
            for nxt in lines[i+1:]:
                v = nxt.strip()
                if not v:
                    continue
                if v.startswith('#'):
                    break
                vals.append(v)
            if vals:
                return ' '.join(vals)
    return fallback

def normalize_status(v):
    v = v.strip().lower().strip('`*_ -')
    if 'no-design-blocker' in v or 'no blocker' in v or 'no-blocker' in v or 'unblocked' in v:
        return 'idle'
    if v.startswith('waiting_on_'):
        return 'working'
    if v.startswith('waiting for ') or v.startswith('waiting on ') or v.startswith('waiting_'):
        return 'idle'
    if 'block' in v or 'stuck' in v: return 'blocked'
    if 'done' in v or 'complete' in v or 'approved' in v or 'pass' in v: return 'done'
    if 'work' in v or 'progress' in v or 'doing' in v or 'active' in v: return 'working'
    if 'offline' in v or 'down' in v: return 'offline'
    if 'idle' in v and 'online' in v: return 'idle'
    if v in ('idle','waiting','standby','ready'): return 'idle'
    if v in (
        'working','in progress','busy','in planning','planned','monitoring qa in progress',
        'monitoring','reviewing','active','ongoing','running','tracking'
    ): return 'working'
    if v in ('done','completed','finished','resolved'): return 'done'
    if v in ('blocked','stuck','waiting on dependency','waiting on approval'): return 'blocked'
    if v in ('offline','down'): return 'offline'
    return v

def slugify_text(v):
    v = (v or '').strip().lower()
    v = re.sub(r'[^a-z0-9]+', '-', v)
    v = re.sub(r'-+', '-', v).strip('-')
    return v or 'unknown'

def infer_work_item(*values):
    joined = ' '.join([x for x in values if x])
    m = re.search(r'(cr[-\s_.]*\d+(?:\.\d+)*(?:[-\s_.]*[a-z0-9]+)*)', joined, re.IGNORECASE)
    if m:
        return slugify_text(m.group(1))
    m = re.search(r'(tc[-\s_.]*\d+(?:[-\s_.]*[a-z0-9]+)*)', joined, re.IGNORECASE)
    if m:
        return slugify_text(m.group(1))
    m = re.search(r'(login[-\s_.]*flow|auth[-\s_.]*contract|rate[-\s_.]*limit)', joined, re.IGNORECASE)
    if m:
        return slugify_text(m.group(1))
    return 'unknown'

def infer_requested_by(status_text, slug, artifact_type):
    explicit = pick_field(status_text, 'requested by', '') or pick_field(status_text, 'Requested By', '')
    if explicit:
        return slugify_text(explicit)
    if slug in ('qa', 'frontend', 'backend'):
        return 'pm'
    if slug in ('pm', 'techlead', 'cto', 'sa', 'ba'):
        return 'ceo'
    if artifact_type in ('decision-summary',):
        return 'human'
    return 'unknown'

def infer_origin_type(src, artifact_type):
    s = str(src).lower()
    if src.name.lower() == 'status.md':
        return 'status'
    if 'report' in s:
        return 'report'
    if 'screenshots' in s or artifact_type in ('evidence-image', 'evidence-video'):
        return 'capture'
    if 'tasks' in s:
        return 'execution-plan'
    return 'file'

def infer_status(text):
    # format: - current status: working  / - **Status:** In Progress
    for line in text.splitlines():
        s=line.strip()
        m = re.match(r'-?\s*current\s+status\s*:\s*(.+)', s, re.IGNORECASE)
        if m:
            return normalize_status(m.group(1))
        m = re.match(r'-\s*\*\*status\*\*:\s*(.+)', s, re.IGNORECASE)
        if m:
            return normalize_status(m.group(1))
        m = re.match(r'-\s*status\s*:\s*(.+)', s, re.IGNORECASE)
        if m:
            return normalize_status(m.group(1))

    # format: ## Status\nworking
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower() == '## status':
            vals=[]
            for nxt in lines[i+1:]:
                v = nxt.strip()
                if not v:
                    continue
                if v.startswith('#'):
                    break
                vals.append(v)
            if vals:
                return normalize_status(' '.join(vals))
    return 'idle'

def status_file_for(slug):
    workspace_status = Path(f'/data/.openclaw/workspace-{slug}/STATUS.md')
    shared_status = Path(shared_root) / slug / 'STATUS.md'
    candidates = [p for p in (shared_status, workspace_status) if p.exists()]
    if not candidates:
        return workspace_status

    def score(path):
        try:
            body = path.read_text(encoding='utf-8')
            canonical = 1 if re.search(r'current\s+status\s*:', body, re.IGNORECASE) else 0
            refreshed = 1 if re.search(r'refreshed_at\s*:', body, re.IGNORECASE) else 0
            return (canonical + refreshed, path.stat().st_mtime)
        except Exception:
            return (0, 0)

    return max(candidates, key=score)

items = []
for slug, acfg in agents_config.items():
    status_file = status_file_for(slug)
    home = agent_homes.get(slug, {'x': 10, 'y': 10})

    if status_file.exists():
        text = status_file.read_text(encoding='utf-8')
        status = infer_status(text)
        objective = pick_field(text, 'current objective', pick_field(text, 'initiative', pick_field(text, 'task', pick_field(text, 'Current Objective', 'Waiting for next task'))))
        next_action = pick_field(text, 'next action', pick_field(text, 'Next Action', ''))
        last_output = pick_field(text, 'last meaningful output', pick_field(text, 'summary', pick_field(text, 'Last Meaningful Output', 'No recent output')))
        m = re.search(r'refreshed_at:\s*(.+)', text)
        if m:
            updated = m.group(1).strip()
        else:
            updated = path_mtime_iso(status_file)

        obj_lower = objective.lower()
        out_lower = last_output.lower()
        combo = obj_lower + ' ' + out_lower
        location = 'desk'
        active_status = status in ('working', 'blocked')
        if active_status and re.search(r'\b(location|room|join|joins|joined|at)\s*[:=-]?\s*meeting\b|\bin\s+(the\s+)?meeting\b', combo) and 'review' not in combo and 'spec' not in combo and 'dashboard' not in combo:
            location = 'meeting'
        elif 'coffee' in combo or 'lounge' in combo:
            location = 'lounge'
        elif 'qa' in combo or 'test' in combo or 'bug' in combo or 'release' in combo or 'staging' in combo:
            location = 'qa-room' if slug in ('qa', 'frontend', 'backend') else 'devops-room' if slug == 'devops' else 'desk'
        elif 'deploy' in combo or 'infra' in combo or 'ci/cd' in combo or 'monitor' in combo:
            location = 'devops-room'
        elif status == 'working' and slug in ('ceo', 'cto', 'techlead', 'pm', 'ba', 'sa'):
            location = 'desk'  # stay at desk, not meeting
        elif status == 'working' and slug in ('frontend', 'backend', 'designer', 'data'):
            location = 'dev-room'
        elif status == 'working' and slug == 'qa':
            location = 'qa-room'
        elif status == 'working' and slug == 'devops':
            location = 'devops-room'
        elif status == 'working' and slug == 'support':
            location = 'support-desk'

        thoughts = {
            'working': [objective, last_output[:80] if last_output else 'working...', 'focus mode'],
            'idle': ['idle', 'waiting for work', 'ready'],
            'blocked': ['blocked...', 'needs help'],
        }
        thought_list = thoughts.get(status, ['...'])
        thought = thought_list[hash(updated) % len(thought_list)]
    else:
        text = ''
        next_action = ''
        status, objective, last_output, updated, location, thought = 'offline', 'No status', 'N/A', 'never', 'desk', 'not online yet'

    recent_task = None
    latest_task = latest_task_by_agent.get(slug)
    if latest_task:
        task_age = task_event_age_seconds(latest_task)
        task_is_recent = task_age is not None and task_age <= TASK_TALK_SECONDS
        task_preview = task_event_preview(latest_task)
        recent_task = {
            'sendId': latest_task.get('sendId', ''),
            'from': latest_task.get('from', 'human'),
            'to': latest_task.get('to', slug),
            'workflowId': latest_task.get('workflowId', ''),
            'summary': task_preview,
            'delivery': latest_task.get('delivery', ''),
            'detail': latest_task.get('detail', ''),
            'sentAt': latest_task.get('ts', ''),
            'ageSeconds': task_age,
            'isRecent': bool(task_is_recent),
        }
        if task_is_recent:
            location = 'talk'
            thought = f"New task: {task_preview[:72]}"
            if status in ('idle', 'offline', 'done'):
                status = 'working'
            if objective in ('Waiting for next task', 'No status', 'initialized and waiting for tasks'):
                objective = task_preview[:160]
            if not next_action:
                next_action = task_preview[:160]
            if last_output in ('N/A', 'No recent output', 'agent initialized', ''):
                last_output = f"Task received from {recent_task['from']}: {task_preview[:160]}"
            event_dt = parse_ts(latest_task.get('ts', ''))
            updated_dt = parse_ts(updated)
            if event_dt and event_dt.tzinfo is None:
                event_dt = event_dt.replace(tzinfo=datetime.timezone.utc)
            if updated_dt and updated_dt.tzinfo is None:
                updated_dt = updated_dt.replace(tzinfo=datetime.timezone.utc)
            if event_dt and (not updated_dt or event_dt > updated_dt):
                updated = latest_task.get('ts', updated)

    items.append({
        'id': slug, 'name': acfg.get('name', slug), 'emoji': acfg.get('emoji', '🤖'),
        'role': acfg.get('role', ''), 'status': status, 'objective': objective,
        'nextAction': next_action, 'lastOutput': last_output, 'updatedAt': updated, 'location': location,
        'speech': thought, 'thought': thought,
        'recentTask': recent_task,
        'blocker': blocker_from_status(status, text, next_action),
        'stale': stale_summary(updated, status),
        'evidenceLinks': [],
        'color': acfg.get('color', '#999'), 'hair': acfg.get('hair', 'short'),
        'hairColor': acfg.get('hairColor', '#3a2a1a'), 'shirt': acfg.get('shirt', acfg.get('color', '#999')),
        'pants': acfg.get('pants', '#3a3a5a'), 'shoes': acfg.get('shoes', '#2a2a3a'),
        'accessory': acfg.get('accessory', ''), 'homeX': home.get('x', 10), 'homeY': home.get('y', 10),
    })

# Also write rooms and homes for dashboard
with open(out_file, 'w', encoding='utf-8') as f:
    json.dump({
        'agents': items,
        'rooms': rooms,
        'agentHomes': agent_homes,
        'meta': generated_meta(warnings=[] if Path(shared_root).exists() else ['shared agent status root not found']),
    }, f, ensure_ascii=False, indent=2)

print(f'Wrote {out_file} ({len(items)} agents)')

# ---- Generate kanban.json from STATUS.md ----
kanban_file = os.path.join(os.path.dirname(out_file), 'kanban.json')

def parse_section(text, heading):
    """Extract content under a ## heading until next ## or end."""
    lines = text.splitlines()
    buf = []
    capture = False
    for line in lines:
        if line.strip().lower().startswith('## '):
            if capture:
                break
            if line.strip().lower() == f'## {heading}'.lower():
                capture = True
            continue
        if capture:
            s = line.strip()
            if s:
                buf.append(s)
    return '\n'.join(buf).strip()

def parse_kv(text, key):
    """Find '- key: value' pattern."""
    for line in text.splitlines():
        m = re.match(r'-\s*\*\*' + re.escape(key) + r'\*\*:\s*(.+)', line.strip())
        if m: return m.group(1).strip()
        m = re.match(r'-\s*' + re.escape(key) + r':\s*(.+)', line.strip(), re.IGNORECASE)
        if m: return m.group(1).strip()
    return ''

def slugify_name(v):
    return re.sub(r'[^a-z0-9]+', '', (v or '').lower())

cards = []
canonical_statuses = {'idle', 'working', 'blocked', 'done'}
weak_output_markers = {
    'working on it', 'investigating', 'continue working', 'monitoring', 'tracking', 'ongoing', 'active'
}
for slug, acfg in agents_config.items():
    workspace_dir = str(workspace_dir_for(slug))
    status_file = status_file_for(slug)
    if not status_file.exists():
        continue
    text = status_file.read_text(encoding='utf-8')

    task = (parse_kv(text, 'Task') or
            parse_kv(text, 'Current Task') or
            pick_field(text, 'current objective', '') or
            pick_field(text, 'Current Objective', '') or
            parse_kv(text, 'Initiative') or
            parse_section(text, 'Current Objective') or
            parse_section(text, 'Current Task') or
            parse_section(text, 'Summary') or '')
    if not task:
        # Fallback: use first meaningful line
        for line in text.splitlines():
            s = line.strip()
            if not s or s.startswith('#') or s.startswith('---') or s.startswith('-'): continue
            task = s[:80]
            break
    if not task:
        continue

    raw_status = infer_status(text)
    status_literal = parse_section(text, 'Status') or parse_kv(text, 'Status') or raw_status
    owner_name = acfg.get('name', slug)
    owner_emoji = acfg.get('emoji', '🤖')

    next_action = (parse_section(text, 'Next Action') or parse_section(text, 'Next Steps') or parse_kv(text, 'Next Action') or '').strip()
    last_output = (parse_section(text, 'Last Meaningful Output') or parse_section(text, 'Summary') or parse_kv(text, 'Last Meaningful Output') or '').strip()
    recent_card_task = latest_task_by_agent.get(slug)
    recent_card_preview = ''
    if recent_card_task and is_recent_task_event(recent_card_task):
        recent_card_preview = task_event_preview(recent_card_task)
        if raw_status in ('idle', 'offline', 'done'):
            raw_status = 'working'
            status_literal = 'working'
        if task in ('Waiting for next task', 'No status', 'initialized and waiting for tasks'):
            task = recent_card_preview
        if not next_action:
            next_action = recent_card_preview
        if not last_output:
            last_output = f"Task received from {recent_card_task.get('from', 'human')}: {recent_card_preview}"
    work_item = (parse_section(text, 'Work Item') or parse_kv(text, 'Work Item') or '').strip()
    if not work_item or work_item in ('none', 'unknown'):
        guessed = infer_work_item(task, next_action, last_output)
        work_item = guessed if guessed != 'unknown' else (work_item or 'none')

    plan = (parse_section(text, 'Implementation Plan') or
            parse_section(text, 'Design Plan') or
            parse_section(text, 'Test Plan') or
            parse_section(text, 'Infra Plan') or
            parse_section(text, 'Deliverables') or
            parse_section(text, 'Next Steps') or
            parse_section(text, 'Next Action') or '')
    plan_short = '. '.join(plan.split('\n')[:3])[:200]

    deliverables = parse_section(text, 'Deliverables') or ''
    blockers_detail = parse_section(text, 'Blockers') or parse_section(text, 'Active Blockers') or ''
    acceptance = parse_section(text, 'Acceptance Criteria') or ''
    owner_notes = parse_section(text, 'Owner Notes') or parse_section(text, 'Notes') or ''
    collab = parse_section(text, 'Collaboration') or ''
    collab_short = '. '.join(collab.split('\n')[:2])[:120]

    warnings = []
    literal_norm = normalize_status(status_literal)
    if literal_norm not in canonical_statuses:
        warnings.append({
            'type': 'status-format',
            'label': f'Non-canonical status: {status_literal[:40]}'
        })
    elif status_literal.strip().lower() != literal_norm:
        warnings.append({
            'type': 'status-format',
            'label': f'Status should be plain `{literal_norm}`'
        })

    if raw_status == 'blocked':
        warnings.append({'type': 'blocked', 'label': 'Blocked, needs owner follow-up'})
        if not next_action:
            warnings.append({'type': 'blocked', 'label': 'Blocked without clear next action'})
        if not collab_short:
            warnings.append({'type': 'blocked', 'label': 'Blocked without collaboration owner'})

    lo = last_output.strip().lower()
    if lo and any(marker == lo or marker in lo for marker in weak_output_markers):
        warnings.append({'type': 'weak-output', 'label': 'Last output is vague'})

    if raw_status == 'working' and not next_action:
        warnings.append({'type': 'missing-next', 'label': 'Working without next action'})

    try:
        age_minutes = int((utc_now() - datetime.datetime.fromtimestamp(status_file.stat().st_mtime, datetime.timezone.utc)).total_seconds() // 60)
    except Exception:
        age_minutes = None
    if recent_card_task and is_recent_task_event(recent_card_task):
        task_age_seconds = task_event_age_seconds(recent_card_task)
        if task_age_seconds is not None:
            age_minutes = task_age_seconds // 60
    card_updated_at = path_mtime_iso(status_file)
    if recent_card_task and is_recent_task_event(recent_card_task):
        card_updated_at = recent_card_task.get('ts') or card_updated_at

    if age_minutes is not None:
        if raw_status == 'working' and age_minutes >= 30:
            warnings.append({'type': 'stale', 'label': f'No status update for {age_minutes}m while working'})
        if raw_status == 'blocked' and age_minutes >= 15:
            warnings.append({'type': 'stale', 'label': f'Blocked for {age_minutes}m without refresh'})
        if raw_status in ('idle', 'done') and age_minutes >= 180:
            warnings.append({'type': 'stale', 'label': f'Status not refreshed for {age_minutes}m'})

    escalation_score = 0
    escalation_owner = ''
    if raw_status == 'blocked':
        escalation_score += 60
        escalation_owner = 'CEO'
    if any(w['type'] == 'stale' for w in warnings):
        escalation_score += 30
        escalation_owner = escalation_owner or ('PM' if raw_status == 'working' else 'CEO')
    if any(w['type'] == 'status-format' for w in warnings):
        escalation_score += 10
        escalation_owner = escalation_owner or 'PM'
    if any(w['type'] == 'missing-next' for w in warnings):
        escalation_score += 15
        escalation_owner = escalation_owner or 'PM'
    if any(w['type'] == 'weak-output' for w in warnings):
        escalation_score += 10
        escalation_owner = escalation_owner or 'PM'
    if raw_status == 'blocked' and age_minutes is not None and age_minutes >= 30:
        escalation_score += 20
        escalation_owner = 'CEO'
    if raw_status == 'working' and age_minutes is not None and age_minutes >= 60:
        escalation_score += 15
        escalation_owner = escalation_owner or 'PM'

    # Map status to kanban stage
    if raw_status in ('done', 'completed'):
        stage = 'done'
    elif raw_status == 'blocked':
        stage = 'blocked'
    elif raw_status == 'working':
        stage = 'doing'
    else:
        stage = 'todo'

    screenshots = []
    videos = []
    src_dir = Path(workspace_dir) / 'screenshots'
    dst_dir = Path(screen_dir) / slug
    if src_dir.exists() and src_dir.is_dir():
        dst_dir.mkdir(parents=True, exist_ok=True)
        for src in sorted(src_dir.iterdir()):
            if src.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp', '.gif'}:
                continue
            dst = dst_dir / src.name
            try:
                shutil.copy2(src, dst)
                screenshots.append({
                    'src': f"data/screenshots/{slug}/{src.name}",
                    'label': src.stem.replace('_',' ').replace('-',' ')
                })
            except Exception:
                pass

    # Videos (webm/mp4) from intentional evidence locations only
    video_sources = [
        Path(workspace_dir) / 'screenshots' / 'videos',
        Path(workspace_dir) / 'reports' / 'test-results',
    ]
    projects_dir = Path(workspace_dir) / 'projects'
    if projects_dir.exists() and projects_dir.is_dir():
        video_sources.extend(projects_dir.glob('*/reports/test-results'))
    video_dst_dir = Path(screen_dir).parent / 'videos' / slug
    seen_video_names = set()
    for video_dir in video_sources:
        if not video_dir.exists() or not video_dir.is_dir():
            continue
        video_dst_dir.mkdir(parents=True, exist_ok=True)
        for src in sorted(video_dir.rglob('*')):
            if src.is_dir():
                continue
            if src.suffix.lower() not in {'.webm', '.mp4'}:
                continue
            dst_name = src.name
            if dst_name in seen_video_names:
                continue
            dst = video_dst_dir / dst_name
            try:
                shutil.copy2(src, dst)
                seen_video_names.add(dst_name)
                videos.append({
                    'src': f"data/videos/{slug}/{dst_name}",
                    'label': src.parent.name.replace('_',' ').replace('-',' ') if src.parent.name else src.stem.replace('_',' ').replace('-',' ')
                })
            except Exception:
                pass

    pm_tasks = None
    if slug == 'pm':
        pm_tasks_path = Path(workspace_dir) / 'PM_TASKS.md'
        if pm_tasks_path.exists():
            lines = pm_tasks_path.read_text(encoding='utf-8').splitlines()
            checklist = []
            current = []
            waiting = []
            blockers = []
            section = None
            for line in lines:
                s = line.strip()
                if s.lower() == '## checklist': section = 'checklist'; continue
                if s.lower() == '## current focus': section = 'focus'; continue
                if s.lower() == '## waiting / dependencies': section = 'waiting'; continue
                if s.lower() == '## blockers': section = 'blockers'; continue
                if s.startswith('## '): section = None; continue
                if not s: continue
                if section == 'checklist' and s.startswith('- ['):
                    done = s.startswith('- [x]') or s.startswith('- [X]')
                    label = s[6:].strip()
                    checklist.append({'done': done, 'label': label})
                elif section == 'focus' and s.startswith('- '):
                    current.append(s[2:].strip())
                elif section == 'waiting' and s.startswith('- '):
                    waiting.append(s[2:].strip())
                elif section == 'blockers' and s.startswith('- '):
                    blockers.append(s[2:].strip())
            pm_tasks = {
                'checklist': checklist,
                'doneCount': sum(1 for x in checklist if x['done']),
                'totalCount': len(checklist),
                'focus': current,
                'waiting': waiting,
                'blockers': blockers,
            }

    escalation = None
    required_action = ''
    if escalation_score > 0:
        escalation = {
            'score': escalation_score,
            'owner': escalation_owner,
            'level': 'high' if escalation_score >= 70 else 'medium' if escalation_score >= 30 else 'low'
        }
        if raw_status == 'blocked':
            required_action = f"{escalation_owner} must follow up and clear blocker owner/action now"
        elif any(w['type'] == 'stale' for w in warnings):
            required_action = f"{escalation_owner} must request a fresh status/output update now"
        elif any(w['type'] == 'missing-next' for w in warnings):
            required_action = f"{escalation_owner} must make the owner define the next action"
        elif any(w['type'] == 'status-format' for w in warnings):
            required_action = f"{escalation_owner} must normalize STATUS.md format"
        elif any(w['type'] == 'weak-output' for w in warnings):
            required_action = f"{escalation_owner} must request a more concrete output update"

    cards.append({
        'id': slug,
        'workItem': work_item,
        'title': task[:80],
        'owner': owner_name,
        'ownerId': slug,
        'emoji': owner_emoji,
        'color': acfg.get('color', '#999'),
        'status': raw_status,
        'stage': stage,
        'plan': plan_short,
        'nextAction': next_action[:200],
        'lastOutput': last_output[:200],
        'recentTask': {
            'sendId': recent_card_task.get('sendId', ''),
            'from': recent_card_task.get('from', 'human'),
            'workflowId': recent_card_task.get('workflowId', ''),
            'summary': task_event_preview(recent_card_task),
            'delivery': recent_card_task.get('delivery', ''),
            'sentAt': recent_card_task.get('ts', ''),
            'ageSeconds': task_event_age_seconds(recent_card_task),
            'isRecent': is_recent_task_event(recent_card_task),
        } if recent_card_task else None,
        'blocker': blocker_from_status(raw_status, text, next_action),
        'stale': {
            'level': 'stale' if any(w['type'] == 'stale' for w in warnings) else 'fresh',
            'ageMinutes': age_minutes,
            'reason': next((w['label'] for w in warnings if w['type'] == 'stale'), ''),
        },
        'evidenceLinks': [
            {
                'label': 'Status',
                'href': f'data/artifacts/{slug}/STATUS.md',
            }
        ],
        'collaboration': collab_short,
        'details': {
            'deliverables': [x.strip('- ').strip() for x in deliverables.split('\n') if x.strip()][:8],
            'blockers': [x.strip('- ').strip() for x in blockers_detail.split('\n') if x.strip()][:8],
            'acceptanceCriteria': [x.strip('- ').strip() for x in acceptance.split('\n') if x.strip()][:8],
            'ownerNotes': [x.strip('- ').strip() for x in owner_notes.split('\n') if x.strip()][:8],
        },
        'role': acfg.get('role', ''),
        'updatedAt': card_updated_at,
        'ageMinutes': age_minutes,
        'screenshots': screenshots,
        'videos': videos,
        'pmTasks': pm_tasks,
        'warnings': warnings,
        'escalation': escalation,
        'requiredAction': required_action,
    })

card_by_slug = {c['id']: c for c in cards}
role_aliases = {}
for slug, acfg in agents_config.items():
    aliases = {
        slugify_name(slug),
        slugify_name(acfg.get('name', '')),
        slugify_name(acfg.get('role', '')),
    }
    if slug == 'cto':
        aliases.update({'solutionarchitecture', 'sa', 'architecture'})
    if slug == 'ceo':
        aliases.update({'human'})
    role_aliases[slug] = {a for a in aliases if a}

existing_card_ids = {c.get('id') for c in cards}
for slug, acfg in agents_config.items():
    if slug in existing_card_ids:
        continue
    cards.append({
        'id': slug,
        'workItem': 'none',
        'title': 'No STATUS.md available - agent remains on roster',
        'owner': acfg.get('name', slug),
        'ownerId': slug,
        'emoji': acfg.get('emoji', '🤖'),
        'color': acfg.get('color', '#999'),
        'status': 'offline',
        'stage': 'todo',
        'plan': '',
        'nextAction': 'PM must restore or refresh the agent STATUS.md',
        'lastOutput': 'No status file found during dashboard generation.',
        'blocker': {
            'isBlocked': True,
            'owner': 'PM',
            'missingInput': f'{slug} STATUS.md',
            'nextAction': 'PM must restore or refresh the agent STATUS.md',
        },
        'stale': {
            'level': 'stale',
            'ageMinutes': None,
            'reason': 'missing STATUS.md',
        },
        'evidenceLinks': [
            {
                'label': 'Status',
                'href': f'data/artifacts/{slug}/STATUS.md',
            }
        ],
        'collaboration': '',
        'details': {
            'deliverables': [],
            'blockers': [f'{slug} STATUS.md missing'],
            'acceptanceCriteria': [],
            'ownerNotes': [],
        },
        'role': acfg.get('role', ''),
        'updatedAt': generated_at,
        'ageMinutes': None,
        'screenshots': [],
        'videos': [],
        'pmTasks': None,
        'warnings': [{'type': 'missing-status', 'label': 'Agent STATUS.md missing'}],
        'escalation': {'score': 60, 'owner': 'PM', 'level': 'medium'},
        'requiredAction': f'PM must restore or refresh {slug} STATUS.md',
    })

for card in cards:
    text_blob = ' '.join([card.get('collaboration', ''), card.get('nextAction', ''), card.get('lastOutput', '')]).lower()
    if card.get('status') != 'working' or card.get('workItem') in ('', 'none', 'unknown'):
        continue
    downstream = []
    for slug, aliases in role_aliases.items():
        if slug == card['id']:
            continue
        slug_mentions = []
        for alias in aliases:
            if not alias or len(alias) < 3:
                continue
            if alias in slugify_name(text_blob):
                slug_mentions.append(alias)
        if slug_mentions:
            downstream.append(slug)
    downstream = sorted(set(downstream))
    idle_targets = []
    for slug in downstream:
        target = card_by_slug.get(slug)
        if not target:
            continue
        if target.get('status') == 'idle' and target.get('workItem') in ('', 'none', 'unknown'):
            idle_targets.append(target.get('owner') or slug)
    if idle_targets:
        card['warnings'].append({
            'type': 'handoff-gap',
            'label': 'Downstream owner(s) still idle: ' + ', '.join(idle_targets[:4])
        })
        extra_score = 25 if len(idle_targets) == 1 else 35
        current = card.get('escalation') or {'score': 0, 'owner': 'PM', 'level': 'low'}
        score = current.get('score', 0) + extra_score
        owner = 'CEO' if card['id'] in ('ceo', 'cto', 'ba') else (current.get('owner') or 'PM')
        card['escalation'] = {
            'score': score,
            'owner': owner,
            'level': 'high' if score >= 70 else 'medium' if score >= 30 else 'low'
        }
        card['requiredAction'] = f"{owner} must land the handoff to active owners now ({', '.join(idle_targets[:4])})"

cards.sort(key=lambda c: (-(c.get('escalation') or {}).get('score', 0), c.get('owner', '')))

with open(kanban_file, 'w', encoding='utf-8') as f:
    json.dump({
        'cards': cards,
        'updated': generated_at,
        'meta': generated_meta(warnings=[] if Path(shared_root).exists() else ['shared agent status root not found']),
    }, f, ensure_ascii=False, indent=2)
print(f'Wrote {kanban_file} ({len(cards)} cards)')

# ---------------- Evidence layer ----------------
artifacts_dir = Path(out_dir) / 'artifacts'
if artifacts_dir.exists():
    shutil.rmtree(artifacts_dir)
artifacts_dir.mkdir(parents=True, exist_ok=True)

agent_files_dir = Path(out_dir) / 'agent-files'
if agent_files_dir.exists():
    shutil.rmtree(agent_files_dir)
agent_files_dir.mkdir(parents=True, exist_ok=True)

agent_file_manifest = []
allowed_agent_files = ['AGENTS.md', 'SOUL.md', 'IDENTITY.md', 'TOOLS.md', 'USER.md', 'STATUS.md']
for slug, acfg in agents_config.items():
    workspace_dir = workspace_dir_for(slug)
    role_dir = agent_files_dir / slug
    role_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for name in allowed_agent_files:
        src = workspace_dir / name
        if src.exists() and src.is_file():
            try:
                shutil.copy2(src, role_dir / name)
                files.append({'label': name, 'path': f'data/agent-files/{slug}/{name}'})
            except Exception:
                pass
    shared_status = Path(shared_root) / slug / 'STATUS.md'
    if shared_status.exists() and shared_status.is_file():
        try:
            shutil.copy2(shared_status, role_dir / 'SHARED_STATUS.md')
            files.append({'label': 'SHARED_STATUS.md', 'path': f'data/agent-files/{slug}/SHARED_STATUS.md'})
        except Exception:
            pass
    agent_file_manifest.append({
        'id': slug,
        'name': acfg.get('name', slug),
        'emoji': acfg.get('emoji', ''),
        'files': files,
    })

with open(agent_files_dir / 'manifest.json', 'w', encoding='utf-8') as f:
    json.dump({'agents': agent_file_manifest, 'updated': generated_at}, f, ensure_ascii=False, indent=2)

role_patterns = {
    'qa': [
        ('reports/*.md', 'report'),
        ('*report.json', 'test-result'),
        ('screenshots/*latest.png', 'evidence-image'),
        ('screenshots/videos/*.webm', 'evidence-video'),
        ('screenshots/videos/*.mp4', 'evidence-video'),
        ('QA_REPORT_TEMPLATE.md', 'template'),
        ('QA_RISK_BASED_TESTING.md', 'strategy'),
    ],
    'ba': [
        ('*BRD*.md', 'requirement'),
        ('*ACCEPTANCE*.md', 'acceptance-criteria'),
        ('*QUESTIONS*.md', 'open-questions'),
        ('requirements/*.md', 'requirement'),
    ],
    'sa': [
        ('*SPEC*.md', 'system-spec'),
        ('*REQUIREMENT_ANALYSIS*.md', 'analysis'),
        ('specs/*.md', 'system-spec'),
    ],
    'pm': [
        ('PM_TASKS.md', 'execution-plan'),
        ('STATUS.md', 'status'),
        ('screenshots/*.png', 'evidence-image'),
        ('screenshots/*.jpg', 'evidence-image'),
        ('screenshots/*.jpeg', 'evidence-image'),
        ('screenshots/*.webp', 'evidence-image'),
    ],
    'cto': [
        ('STATUS.md', 'solution-summary'),
    ],
    'techlead': [
        ('STATUS.md', 'review-summary'),
        ('projects/*/reports/test-results/**/*.webm', 'evidence-video'),
        ('projects/*/reports/test-results/**/*.mp4', 'evidence-video'),
    ],
    'frontend': [
        ('STATUS.md', 'implementation-status'),
    ],
    'backend': [
        ('STATUS.md', 'implementation-status'),
        ('docs/*.md', 'technical-note'),
    ],
    'ceo': [('STATUS.md', 'decision-summary')],
    'devops': [('STATUS.md', 'runtime-status')],
    'data': [('STATUS.md', 'data-status')],
    'designer': [('STATUS.md', 'design-status')],
    'support': [('STATUS.md', 'support-status')],
}

artifacts = []
for slug, acfg in agents_config.items():
    workspace_dir = workspace_dir_for(slug)
    status_text = ''
    status_path = workspace_dir / 'STATUS.md'
    shared_status_path = Path(shared_root) / slug / 'STATUS.md'
    if not status_path.exists() and shared_status_path.exists():
        status_path = shared_status_path
    if status_path.exists():
        try:
            status_text = status_path.read_text(encoding='utf-8')
        except Exception:
            status_text = ''
    objective_hint = pick_field(status_text, 'Current Objective', '') or pick_field(status_text, 'current objective', '')
    card_hint = pick_field(status_text, 'Card ID', '') or pick_field(status_text, 'card id', '') or slug
    work_item_hint = pick_field(status_text, 'Work Item', '') or pick_field(status_text, 'work item', '') or infer_work_item(objective_hint)
    requested_by_hint = infer_requested_by(status_text, slug, '')
    role_out_dir = artifacts_dir / slug
    role_out_dir.mkdir(parents=True, exist_ok=True)
    seen = set()
    role_sources = []
    if status_path.exists():
        role_sources.append((status_path, 'status'))
    if workspace_dir.exists():
        for pattern, artifact_type in role_patterns.get(slug, [('STATUS.md', 'status')]):
            for src in sorted(workspace_dir.glob(pattern), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True):
                role_sources.append((src, artifact_type))
    for src, artifact_type in role_sources:
        matches = [src]
        for src in matches:
            if not src.is_file():
                continue
            key = str(src.resolve())
            if key in seen:
                continue
            seen.add(key)
            dst = role_out_dir / src.name
            try:
                shutil.copy2(src, dst)
            except Exception:
                continue
            title = src.stem.replace('_', ' ').replace('-', ' ')
            if artifact_type == 'requirement':
                title = 'Requirement / BRD'
            elif artifact_type == 'acceptance-criteria':
                title = 'Acceptance Criteria'
            elif artifact_type == 'system-spec':
                title = 'System Spec'
            elif artifact_type == 'execution-plan':
                title = 'Execution Plan / PM Tasks'
            elif artifact_type == 'solution-summary':
                title = 'Solution Direction Summary'
            elif artifact_type == 'review-summary':
                title = 'Review / Delegation Summary'
            elif artifact_type == 'technical-note' and src.name.lower() == 'status.md':
                title = 'Implementation Status'
            mime = mimetypes.guess_type(str(dst))[0] or ''
            work_item = pick_field(status_text, 'Work Item', '') or infer_work_item(src.name, title, objective_hint, work_item_hint)
            card_id = pick_field(status_text, 'Card ID', '') or card_hint or slug
            requested_by = infer_requested_by(status_text, slug, artifact_type) or requested_by_hint
            origin_type = infer_origin_type(src, artifact_type)
            origin_ref = f"{origin_type}:{src.name}"
            ts = __import__('datetime').datetime.fromtimestamp(src.stat().st_mtime).strftime('%Y%m%d-%H%M%S')
            artifact_id = f"{slug}-{slugify_text(work_item)}-{slugify_text(artifact_type)}-{ts}"
            summary = ''
            if src.suffix.lower() in ('.md', '.txt'):
                try:
                    raw = src.read_text(encoding='utf-8', errors='ignore')
                    first = next((ln.strip() for ln in raw.splitlines() if ln.strip() and not ln.strip().startswith('#')), '')
                    summary = first[:220]
                except Exception:
                    summary = ''
            artifacts.append({
                'id': artifact_id,
                'owner': slug,
                'ownerName': acfg.get('name', slug),
                'role': acfg.get('role', ''),
                'workItem': work_item or 'unknown',
                'cardId': card_id or slug,
                'artifactType': artifact_type,
                'title': title,
                'path': f'data/artifacts/{slug}/{dst.name}',
                'sourcePath': str(src),
                'updatedAt': path_mtime_iso(src),
                'requestedBy': requested_by or 'unknown',
                'originType': origin_type,
                'originRef': origin_ref,
                'mimeType': mime,
                'summary': summary,
                'important': True,
                'status': 'current',
            })

workflow_artifact_root = Path(os.environ.get('WORKFLOW_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-workflows')))
def workflow_owner_for(src):
    name = str(src.relative_to(workflow_artifact_root)).lower() if workflow_artifact_root in src.parents else src.name.lower()
    for slug in agents_config:
        if slug in name:
            return slug
    if 'qa-evidence' in name or 'evidence-summary' in name or 'screenshot' in name:
        return 'qa'
    if 'board' in name or 'implementation-plan' in name or 'bug-' in name:
        return 'pm'
    return 'pm'

if workflow_artifact_root.exists():
    for workflow_dir in sorted([p for p in workflow_artifact_root.iterdir() if p.is_dir()], key=lambda p: p.stat().st_mtime, reverse=True)[:10]:
        artifact_root = workflow_dir / 'artifacts'
        if not artifact_root.exists():
            continue
        for src in sorted([p for p in artifact_root.rglob('*') if p.is_file()], key=lambda p: p.stat().st_mtime, reverse=True)[:80]:
            owner = workflow_owner_for(src)
            acfg = agents_config.get(owner, {})
            role_out_dir = artifacts_dir / owner
            role_out_dir.mkdir(parents=True, exist_ok=True)
            rel_name = '-'.join(src.relative_to(artifact_root).parts)
            dst = role_out_dir / rel_name
            try:
                shutil.copy2(src, dst)
            except Exception:
                continue
            mime = mimetypes.guess_type(str(dst))[0] or ''
            suffix = src.suffix.lower()
            artifact_type = 'evidence-image' if suffix in ('.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg') else 'evidence'
            title = src.stem.replace('_', ' ').replace('-', ' ')
            work_item = workflow_dir.name
            ts = __import__('datetime').datetime.fromtimestamp(src.stat().st_mtime).strftime('%Y%m%d-%H%M%S')
            artifacts.append({
                'id': f"{owner}-{slugify_text(work_item)}-{slugify_text(title)}-{ts}",
                'owner': owner,
                'ownerName': acfg.get('name', owner),
                'role': acfg.get('role', ''),
                'workItem': work_item,
                'cardId': owner,
                'artifactType': artifact_type,
                'title': title[:80],
                'path': f'data/artifacts/{owner}/{dst.name}',
                'sourcePath': str(src),
                'updatedAt': path_mtime_iso(src),
                'requestedBy': 'pm',
                'originType': 'workflow-artifact',
                'originRef': f"{workflow_dir.name}:{src.relative_to(artifact_root)}",
                'mimeType': mime,
                'summary': '',
                'important': True,
                'status': 'current',
            })

artifacts.sort(key=lambda a: (a['owner'], a['artifactType'], a['title']))
artifacts_file = str(Path(out_dir) / 'artifacts.json')
with open(artifacts_file, 'w', encoding='utf-8') as f:
    json.dump({
        'artifacts': artifacts,
        'updated': generated_at,
        'meta': generated_meta(warnings=[]),
    }, f, ensure_ascii=False, indent=2)
print(f'Wrote {artifacts_file} ({len(artifacts)} artifacts)')

# ---------------- Workflow activity layer ----------------
workflow_root = Path(os.environ.get('WORKFLOW_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-workflows')))
outbox_root = Path(os.environ.get('OUTBOX_ROOT', str(Path.home() / '.openclaw' / 'shared' / 'company-outbox')))
activities = []
workflows = []

for event in task_send_events:
    activities.append({
        'ts': event.get('ts', ''),
        'workflowId': event.get('workflowId', '') or 'direct-task',
        'kind': 'task_sent',
        'type': 'task_sent',
        'from': event.get('from', 'human'),
        'to': event.get('to', ''),
        'summary': task_event_preview(event),
        'delivery': event.get('delivery', ''),
        'sendId': event.get('sendId', ''),
    })

def read_workflow_objective(workflow_dir):
    wf = workflow_dir / 'WORKFLOW.md'
    if not wf.exists():
        return ''
    text = wf.read_text(encoding='utf-8', errors='ignore')
    return parse_section(text, 'Objective') or ''

if workflow_root.exists():
    for workflow_dir in sorted([p for p in workflow_root.iterdir() if p.is_dir()], key=lambda p: p.stat().st_mtime, reverse=True):
        workflow_id = workflow_dir.name
        objective = read_workflow_objective(workflow_dir)
        handoff_dir = workflow_dir / 'handoffs'
        artifact_dir = workflow_dir / 'artifacts'
        event_count = 0
        latest_ts = ''

        events_file = workflow_dir / 'events.ndjson'
        if events_file.exists():
            for line in events_file.read_text(encoding='utf-8', errors='ignore').splitlines():
                if not line.strip():
                    continue
                try:
                    event = json.loads(line)
                except Exception:
                    continue
                event.setdefault('workflowId', workflow_id)
                event.setdefault('type', 'event')
                event.setdefault('summary', '')
                event.setdefault('from', '')
                event.setdefault('to', '')
                event['kind'] = event.get('type', 'event')
                activities.append(event)
                event_count += 1
                latest_ts = max(latest_ts, event.get('ts', ''))

        if handoff_dir.exists():
            for src in sorted(handoff_dir.glob('*.md'), key=lambda p: p.stat().st_mtime, reverse=True):
                raw = src.read_text(encoding='utf-8', errors='ignore')
                task = parse_section(raw, 'Task') or next((ln.strip('# ').strip() for ln in raw.splitlines() if ln.strip() and not ln.startswith('- workflow_id:')), '')
                meta_from = parse_kv(raw, 'from')
                meta_to = parse_kv(raw, 'to')
                ts = path_mtime_iso(src)
                activities.append({
                    'ts': ts,
                    'workflowId': workflow_id,
                    'kind': 'handoff_file',
                    'type': 'handoff_file',
                    'from': meta_from,
                    'to': meta_to,
                    'summary': task[:240],
                    'path': str(src),
                    'relativePath': f'data/workflows/{workflow_id}/handoffs/{src.name}',
                })
                event_count += 1
                latest_ts = max(latest_ts, ts)

        artifact_count = 0
        if artifact_dir.exists():
            artifact_count = sum(1 for p in artifact_dir.rglob('*') if p.is_file())

        workflows.append({
            'id': workflow_id,
            'objective': objective,
            'handoffCount': len(list(handoff_dir.glob('*.md'))) if handoff_dir.exists() else 0,
            'artifactCount': artifact_count,
            'eventCount': event_count,
            'updatedAt': latest_ts or path_mtime_iso(workflow_dir),
        })

        # Copy workflow files into dashboard data for browser access.
        dst_workflow_dir = Path(out_dir) / 'workflows' / workflow_id
        if dst_workflow_dir.exists():
            shutil.rmtree(dst_workflow_dir)
        if handoff_dir.exists() or artifact_dir.exists() or (workflow_dir / 'WORKFLOW.md').exists():
            dst_workflow_dir.mkdir(parents=True, exist_ok=True)
            for name in ('WORKFLOW.md', 'events.ndjson'):
                src = workflow_dir / name
                if src.exists():
                    shutil.copy2(src, dst_workflow_dir / name)
            if handoff_dir.exists():
                shutil.copytree(handoff_dir, dst_workflow_dir / 'handoffs', dirs_exist_ok=True)
            if artifact_dir.exists():
                shutil.copytree(artifact_dir, dst_workflow_dir / 'artifacts', dirs_exist_ok=True)

if outbox_root.exists():
    for src in sorted(outbox_root.glob('*/*.md'), key=lambda p: p.stat().st_mtime, reverse=True)[:100]:
        agent = src.parent.name
        raw = src.read_text(encoding='utf-8', errors='ignore')
        summary = parse_section(raw, 'Task') or parse_section(raw, 'Objective') or next((ln.strip() for ln in raw.splitlines() if ln.strip() and not ln.startswith('#') and not ln.startswith('- ')), '')
        ts = path_mtime_iso(src)
        activities.append({
            'ts': ts,
            'workflowId': 'outbox',
            'kind': 'queued_message',
            'type': 'queued_message',
            'from': 'router',
            'to': agent,
            'summary': summary[:240] or f'Queued message for {agent}',
            'path': str(src),
        })

activities.sort(key=lambda a: a.get('ts', ''), reverse=True)
activity_file = str(Path(out_dir) / 'activity.json')
with open(activity_file, 'w', encoding='utf-8') as f:
    json.dump({
        'activities': activities[:200],
        'workflows': workflows[:50],
        'updated': generated_at,
        'meta': generated_meta(
            warnings=[] if workflow_root.exists() else [f'workflow root not found: {workflow_root}'],
            workflowRoot=str(workflow_root),
            outboxRoot=str(outbox_root),
        ),
    }, f, ensure_ascii=False, indent=2)
print(f'Wrote {activity_file} ({len(activities[:200])} activities, {len(workflows[:50])} workflows)')

# ---- Generate token-usage.json from Codex session token telemetry ----
def empty_usage():
    return {
        'inputTokens': 0,
        'cachedInputTokens': 0,
        'outputTokens': 0,
        'reasoningOutputTokens': 0,
        'totalTokens': 0,
        'sessions': 0,
    }

def add_usage(target, usage):
    target['inputTokens'] += int(usage.get('input_tokens') or 0)
    target['cachedInputTokens'] += int(usage.get('cached_input_tokens') or 0)
    target['outputTokens'] += int(usage.get('output_tokens') or 0)
    target['reasoningOutputTokens'] += int(usage.get('reasoning_output_tokens') or 0)
    target['totalTokens'] += int(usage.get('total_tokens') or 0)
    target['sessions'] += 1

def parse_session_usage(path):
    provider = 'openai'
    model = ''
    session_id = path.stem
    last_ts = ''
    last_usage = None
    context_window = None
    try:
        with path.open(encoding='utf-8', errors='ignore') as fh:
            for line in fh:
                try:
                    item = json.loads(line)
                except Exception:
                    continue
                typ = item.get('type')
                payload = item.get('payload') if isinstance(item.get('payload'), dict) else {}
                if typ == 'session_meta':
                    provider = payload.get('model_provider') or provider
                    model = payload.get('model') or payload.get('effective_model') or model
                    session_id = payload.get('id') or session_id
                if typ == 'event_msg' and payload.get('type') == 'token_count':
                    info = payload.get('info') if isinstance(payload.get('info'), dict) else {}
                    usage = info.get('total_token_usage') if isinstance(info.get('total_token_usage'), dict) else None
                    if usage:
                        last_usage = usage
                        context_window = info.get('model_context_window') or context_window
                        last_ts = item.get('timestamp') or last_ts
    except Exception:
        return None
    if not last_usage:
        return None
    model_key = f"{provider}/{model or 'default'}"
    return {
        'sessionId': session_id,
        'model': model_key,
        'provider': provider,
        'lastSeen': last_ts or path_mtime_iso(path),
        'contextWindow': context_window,
        'usage': last_usage,
    }

token_agents = []
models_map = {}
totals = empty_usage()
for slug, acfg in agents_config.items():
    agent_root = state_root / 'agents' / slug
    sessions_root = agent_root / 'agent' / 'codex-home' / 'sessions'
    if not sessions_root.exists():
        sessions_root = agent_root / 'sessions'
    session_files = sorted(sessions_root.glob('**/*.jsonl'), key=lambda p: p.stat().st_mtime, reverse=True)[:80] if sessions_root.exists() else []
    agent_total = empty_usage()
    agent_models = {}
    last_seen = ''
    context_windows = {}
    for session_file in session_files:
        parsed = parse_session_usage(session_file)
        if not parsed:
            continue
        usage = parsed['usage']
        model_key = parsed['model']
        if model_key not in agent_models:
            agent_models[model_key] = empty_usage()
        if model_key not in models_map:
            models_map[model_key] = empty_usage()
        add_usage(agent_total, usage)
        add_usage(agent_models[model_key], usage)
        add_usage(models_map[model_key], usage)
        add_usage(totals, usage)
        if parsed.get('contextWindow'):
            context_windows[model_key] = parsed.get('contextWindow')
        if parsed['lastSeen'] > last_seen:
            last_seen = parsed['lastSeen']
    token_agents.append({
        'id': slug,
        'name': acfg.get('name', slug),
        'emoji': acfg.get('emoji', ''),
        'totalTokens': agent_total['totalTokens'],
        'inputTokens': agent_total['inputTokens'],
        'cachedInputTokens': agent_total['cachedInputTokens'],
        'outputTokens': agent_total['outputTokens'],
        'reasoningOutputTokens': agent_total['reasoningOutputTokens'],
        'sessions': agent_total['sessions'],
        'lastSeen': last_seen,
        'models': [
            dict({'model': model_key, 'contextWindow': context_windows.get(model_key)}, **usage)
            for model_key, usage in sorted(agent_models.items(), key=lambda kv: kv[1]['totalTokens'], reverse=True)
        ],
    })

token_models = [
    dict({'model': model_key}, **usage)
    for model_key, usage in sorted(models_map.items(), key=lambda kv: kv[1]['totalTokens'], reverse=True)
]
token_file = str(Path(out_dir) / 'token-usage.json')
with open(token_file, 'w', encoding='utf-8') as f:
    json.dump({
        'agents': sorted(token_agents, key=lambda a: a.get('totalTokens', 0), reverse=True),
        'models': token_models,
        'totals': totals,
        'updated': generated_at,
        'meta': generated_meta(sourceStatus='ok', sessionFileLimitPerAgent=80),
    }, f, ensure_ascii=False, indent=2)
print(f'Wrote {token_file} ({len(token_agents)} agents, {len(token_models)} models)')
PY
