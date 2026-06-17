#!/usr/bin/env bash
set -euo pipefail

# Compact workflow monitor for company-agent control-plane health.
#
# Usage:
#   ./scripts/monitor-workflows.sh                 # report only
#   ./scripts/monitor-workflows.sh --apply         # mark stale delivery/status
#   ./scripts/monitor-workflows.sh --deep          # include runtime/artifact proof
#   ./scripts/monitor-workflows.sh --workflow ID   # limit to one workflow
#
# This script intentionally reads only STATUS.md, events.ndjson tails, and
# delivery-log metadata. It should not grep source trees or large artifacts.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

DEFAULT_OPENCLAW_HOME="$HOME/.openclaw"
for candidate in \
  "${OPENCLAW_STATE_DIR:-}" \
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
APPLY=0
DEEP=0
WORKFLOW_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --deep)
      DEEP=1
      shift
      ;;
    --workflow)
      WORKFLOW_ID="${2:?Missing value for --workflow}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

python3 - "$SHARED_ROOT" "$WORKFLOW_ROOT" "$APPLY" "$WORKFLOW_ID" "$DEEP" <<'PY'
import datetime
import json
import re
import sys
from pathlib import Path

shared_root = Path(sys.argv[1])
workflow_root = Path(sys.argv[2])
apply = sys.argv[3] == "1"
workflow_filter = sys.argv[4]
deep = sys.argv[5] == "1"
state_root = shared_root.parent.parent if shared_root.name == "agents" else Path("/data/.openclaw")

DELIVERING_STALE_MINUTES = 3
ACK_STALE_MINUTES = 5
WORKING_STALE_MINUTES = 20
BLOCKED_STALE_MINUTES = 30
NO_PROOF_MINUTES = 10
PROMISED_ARTIFACT_GRACE_MINUTES = 30
LOG_WINDOW_MINUTES = int(__import__("os").environ.get("MONITOR_LOG_WINDOW_MINUTES", "120"))

def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)

def iso_now():
    return utc_now().isoformat(timespec="seconds").replace("+00:00", "Z")

def parse_ts(value):
    if not value or value in ("never", "none"):
        return None
    try:
        dt = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt.astimezone(datetime.timezone.utc)
    except Exception:
        return None

def age_minutes(value):
    dt = parse_ts(value)
    if not dt:
        return None
    return max(0, int((utc_now() - dt).total_seconds() // 60))

def pick_field(text, field, fallback=""):
    for line in text.splitlines():
        m = re.match(r"-?\s*" + re.escape(field) + r"\s*:\s*(.+)", line.strip(), re.I)
        if m:
            return m.group(1).strip()
    return fallback

def replace_field(text, field, value):
    pattern = re.compile(rf"(^-\s*{re.escape(field)}\s*:\s*).*$", re.I | re.M)
    if pattern.search(text):
        return pattern.sub(lambda m: f"{m.group(1)}{value}", text, count=1)
    return text.rstrip() + f"\n- {field}: {value}\n"

def status_files():
    if not shared_root.exists():
        return []
    return sorted(shared_root.glob("*/STATUS.md"))

def status_event(path):
    text = path.read_text(encoding="utf-8", errors="ignore")
    agent = path.parent.name
    status = pick_field(text, "current status", pick_field(text, "status", "idle")).strip().lower()
    updated = pick_field(text, "refreshed_at", pick_field(text, "updated", ""))
    workflow_id = pick_field(text, "workflow id", "")
    age = age_minutes(updated)
    issue = None
    severity = "ok"

    if workflow_filter and workflow_id != workflow_filter:
        return None

    if status == "delivering" and (age is None or age >= DELIVERING_STALE_MINUTES):
        severity = "stale"
        issue = f"delivery not confirmed for {age}m"
    elif status == "delivered_waiting_for_receiver" and (age is None or age >= ACK_STALE_MINUTES):
        severity = "stale"
        issue = f"receiver did not acknowledge for {age}m"
    elif status == "delivery_failed":
        severity = "stale"
        issue = "delivery failed"
    elif status == "working" and (age is None or age >= WORKING_STALE_MINUTES):
        last = pick_field(text, "last meaningful output", "")
        if not last or last.lower() in ("working", "working on routed handoff", "none"):
            severity = "stale"
            issue = f"working without evidence for {age}m"
        else:
            severity = "aging"
            issue = f"working for {age}m; verify evidence"
    elif status == "blocked" and (age is None or age >= BLOCKED_STALE_MINUTES):
        severity = "aging"
        issue = f"blocked for {age}m"

    return {
        "agent": agent,
        "path": str(path),
        "status": status,
        "workflowId": workflow_id,
        "ageMinutes": age,
        "severity": severity,
        "issue": issue,
        "nextAction": pick_field(text, "next action", ""),
        "lastMeaningfulOutput": pick_field(text, "last meaningful output", ""),
        "objective": pick_field(text, "current objective", ""),
        "_text": text,
    }

def ts_from_ms(value):
    if not value:
        return None
    try:
        return datetime.datetime.fromtimestamp(int(value) / 1000, datetime.timezone.utc)
    except Exception:
        return None

def agent_session_event(agent):
    sessions_index = state_root / "agents" / agent / "sessions" / "sessions.json"
    if not sessions_index.exists():
        return None
    try:
        data = json.loads(sessions_index.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None
    candidates = []
    for key, meta in data.items():
        if not isinstance(meta, dict):
            continue
        candidates.append((int(meta.get("updatedAt") or 0), key, meta))
    if not candidates:
        return None
    _, key, meta = max(candidates, key=lambda item: item[0])
    updated_dt = ts_from_ms(meta.get("updatedAt"))
    started_dt = ts_from_ms(meta.get("startedAt") or meta.get("sessionStartedAt"))
    return {
        "agent": agent,
        "sessionKey": key,
        "sessionId": meta.get("sessionId", ""),
        "status": str(meta.get("status", "unknown")).lower(),
        "updatedAt": updated_dt.isoformat(timespec="seconds").replace("+00:00", "Z") if updated_dt else "",
        "startedAt": started_dt.isoformat(timespec="seconds").replace("+00:00", "Z") if started_dt else "",
        "updated": updated_dt,
        "started": started_dt,
        "sessionFile": meta.get("sessionFile", ""),
        "model": meta.get("model", ""),
    }

ARTIFACT_PATH_RE = re.compile(r"(/data/\.openclaw/shared/company-workflows/[A-Za-z0-9_.-]+/artifacts/[A-Za-z0-9_.-]+\.(?:md|json|ndjson|txt|csv|html))", re.I)

def promised_artifact_paths(status_text, session_file="", workflow_id=""):
    paths = []
    for source in [status_text]:
        paths.extend(ARTIFACT_PATH_RE.findall(source or ""))
    if session_file:
        path = Path(session_file)
        if path.exists() and path.stat().st_size < 2_000_000:
            try:
                tail = "\n".join(path.read_text(encoding="utf-8", errors="ignore").splitlines()[-80:])
                paths.extend(ARTIFACT_PATH_RE.findall(tail))
            except Exception:
                pass
    seen = []
    for p in paths:
        clean = p.rstrip(".,)\\")
        if workflow_id and f"/company-workflows/{workflow_id}/" not in clean:
            continue
        if clean not in seen:
            seen.append(clean)
    return seen

def workflow_artifact_stats(workflow_id, agent):
    if not workflow_id:
        return {"count": 0, "agentCount": 0, "newestAt": "", "newestAgeMinutes": None}
    root = workflow_root / workflow_id / "artifacts"
    files = []
    agent_files = []
    if root.exists():
        for path in root.glob("*"):
            if not path.is_file():
                continue
            files.append(path)
            if agent.lower() in path.name.lower() and not path.name.lower().startswith(f"pm-{agent.lower()}"):
                agent_files.append(path)
    newest = max((p.stat().st_mtime for p in files), default=0)
    newest_dt = datetime.datetime.fromtimestamp(newest, datetime.timezone.utc) if newest else None
    return {
        "count": len(files),
        "agentCount": len(agent_files),
        "newestAt": newest_dt.isoformat(timespec="seconds").replace("+00:00", "Z") if newest_dt else "",
        "newestAgeMinutes": max(0, int((utc_now() - newest_dt).total_seconds() // 60)) if newest_dt else None,
    }

def assignment_time(workflow_id, agent):
    if not workflow_id:
        return None
    candidates = []
    for folder in ("handoffs", "delivery-logs"):
        root = workflow_root / workflow_id / folder
        if not root.exists():
            continue
        for path in root.glob(f"*-to-{agent}.*"):
            try:
                candidates.append(datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc))
            except Exception:
                pass
    return min(candidates) if candidates else None

def deep_events_for(status_events):
    events = []
    for event in status_events:
        agent = event["agent"]
        workflow_id = event.get("workflowId", "")
        if workflow_filter and workflow_id != workflow_filter:
            continue
        session = agent_session_event(agent)
        artifacts = workflow_artifact_stats(workflow_id, agent)
        assigned_at = assignment_time(workflow_id, agent)
        status_updated = parse_ts(pick_field(event.get("_text", ""), "refreshed_at", ""))
        session_after_assignment = bool(session and assigned_at and session.get("started") and session["started"] >= assigned_at)
        session_after_status = bool(session and status_updated and session.get("updated") and session["updated"] >= status_updated)
        proof = {
            "agent": agent,
            "workflowId": workflow_id,
            "status": event["status"],
            "assignmentAt": assigned_at.isoformat(timespec="seconds").replace("+00:00", "Z") if assigned_at else "",
            "session": {k: v for k, v in (session or {}).items() if k not in ("updated", "started")},
            "artifacts": artifacts,
        }
        if not session:
            if event["status"] == "working" and (event["ageMinutes"] is None or event["ageMinutes"] >= NO_PROOF_MINUTES):
                events.append({**proof, "severity": "stale", "issue": "working but no OpenClaw session metadata found"})
            continue
        promised = promised_artifact_paths(event.get("_text", ""), session.get("sessionFile", ""), workflow_id)
        if promised:
            proof["promisedArtifacts"] = promised
            missing = [p for p in promised if not Path(p).exists()]
            if missing and event["status"] in ("working", "blocked"):
                age = event["ageMinutes"]
                sev = "stale" if age is None or age >= PROMISED_ARTIFACT_GRACE_MINUTES else "aging"
                events.append({**proof, "severity": sev, "issue": f"promised artifact missing: {missing[0]}"})
        if event["status"] == "working" and session.get("status") in ("failed", "aborted") and (session_after_assignment or session_after_status):
            events.append({**proof, "severity": "stale", "issue": f"latest OpenClaw session is {session['status']}"})
        elif event["status"] == "working" and artifacts["agentCount"] == 0 and (event["ageMinutes"] is None or event["ageMinutes"] >= NO_PROOF_MINUTES):
            sev = "aging"
            if session.get("status") in ("failed", "aborted"):
                sev = "stale"
            events.append({**proof, "severity": sev, "issue": "working without agent-owned artifact evidence"})
    return events

def mark_status(event):
    path = Path(event["path"])
    text = path.read_text(encoding="utf-8", errors="ignore")
    status = event["status"]
    if status in ("delivering", "delivered_waiting_for_receiver"):
        text = replace_field(text, "current status", "delivery_failed")
        text = replace_field(text, "active blocker", f"{event['issue']}; retry or reassign")
        text = replace_field(text, "next action", "sender/PM must retry delivery or reassign owner")
    elif status == "working":
        text = replace_field(text, "current status", "blocked")
        text = replace_field(text, "active blocker", f"{event['issue']}; owner must provide evidence or blocker")
        text = replace_field(text, "next action", "PM must reset, split, or reassign")
    text = replace_field(text, "refreshed_at", iso_now())
    text = replace_field(text, "last meaningful output", f"workflow monitor marked stale: {event['issue']}")
    path.write_text(text, encoding="utf-8")

def delivery_log_events():
    roots = []
    if workflow_filter:
        roots = [workflow_root / workflow_filter / "delivery-logs"]
    elif workflow_root.exists():
        roots = [p / "delivery-logs" for p in workflow_root.iterdir() if p.is_dir()]
    events = []
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)[:100]:
            size = path.stat().st_size
            text = path.read_text(encoding="utf-8", errors="ignore")[:300] if size else ""
            age = max(0, int((utc_now() - datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc)).total_seconds() // 60))
            if age > LOG_WINDOW_MINUTES:
                continue
            if size == 0 or text.strip().startswith("Sending to ") and len(text.strip().splitlines()) <= 1:
                if age >= ACK_STALE_MINUTES:
                    events.append({
                        "path": str(path),
                        "severity": "stale",
                        "issue": "empty or send-only delivery log",
                        "ageMinutes": age,
                    })
    return events

status_events = [e for e in (status_event(p) for p in status_files()) if e]
delivery_events = delivery_log_events()
deep_events = deep_events_for(status_events) if deep else []
def public_event(event):
    return {k: v for k, v in event.items() if k != "_text"}

problems = [public_event(e) for e in status_events if e["severity"] in ("stale", "aging")] + delivery_events + deep_events

if apply:
    for event in status_events:
        if event["severity"] == "stale":
            mark_status(event)
    for event in deep_events:
        if event.get("severity") == "stale" and event.get("status") == "working":
            path = shared_root / event["agent"] / "STATUS.md"
            if path.exists():
                text = path.read_text(encoding="utf-8", errors="ignore")
                text = replace_field(text, "current status", "blocked")
                text = replace_field(text, "active blocker", f"work reality check failed: {event['issue']}")
                text = replace_field(text, "next action", "Owner must produce artifact evidence or report blocker at Talk; PM may reassign")
                text = replace_field(text, "refreshed_at", iso_now())
                text = replace_field(text, "last meaningful output", f"deep monitor marked blocked: {event['issue']}")
                path.write_text(text, encoding="utf-8")

print(json.dumps({
    "generatedAt": iso_now(),
    "apply": apply,
    "deep": deep,
    "workflowFilter": workflow_filter or None,
    "summary": {
        "statusFiles": len(status_events),
        "problems": len(problems),
        "stale": sum(1 for e in problems if e.get("severity") == "stale"),
        "aging": sum(1 for e in problems if e.get("severity") == "aging"),
    },
    "problems": problems[:50],
}, ensure_ascii=False, indent=2))
PY
