#!/usr/bin/env bash
set -euo pipefail

# Compact workflow monitor for company-agent control-plane health.
#
# Usage:
#   ./scripts/monitor-workflows.sh                 # report only
#   ./scripts/monitor-workflows.sh --apply         # mark stale delivery/status
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
WORKFLOW_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=1
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

python3 - "$SHARED_ROOT" "$WORKFLOW_ROOT" "$APPLY" "$WORKFLOW_ID" <<'PY'
import datetime
import json
import re
import sys
from pathlib import Path

shared_root = Path(sys.argv[1])
workflow_root = Path(sys.argv[2])
apply = sys.argv[3] == "1"
workflow_filter = sys.argv[4]

DELIVERING_STALE_MINUTES = 3
ACK_STALE_MINUTES = 5
WORKING_STALE_MINUTES = 20
BLOCKED_STALE_MINUTES = 30
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
    }

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
problems = [e for e in status_events if e["severity"] in ("stale", "aging")] + delivery_events

if apply:
    for event in status_events:
        if event["severity"] == "stale":
            mark_status(event)

print(json.dumps({
    "generatedAt": iso_now(),
    "apply": apply,
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
