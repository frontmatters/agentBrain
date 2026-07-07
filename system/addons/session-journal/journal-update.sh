#!/usr/bin/env bash
# Core: read a Claude Code transcript JSONL and update local/sessions/session-journal.md
# Usage:
#   journal-update.sh --transcript /path/to/transcript.jsonl [--source stop|autosave|manual]
#   echo '{"transcript_path":"..."}' | journal-update.sh --stdin --source stop
#
# Reads config from local/sessions/journal-config.json (falls back to addon default).
# Idempotent: rewrites the journal body, preserves frontmatter id/previous, refreshes
# `project` and `Last updated`.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
JOURNAL="$BRAIN_ROOT/local/sessions/session-journal.md"
LOCAL_CONFIG="$BRAIN_ROOT/local/sessions/journal-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"

source_label="manual"
transcript_path=""
from_stdin=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--transcript) transcript_path="$2"; shift 2 ;;
		--stdin) from_stdin=1; shift ;;
		--source) source_label="$2"; shift 2 ;;
		--help|-h)
			grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done

# Pick effective config: local overrides default.
config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

# Loud config validation. A corrupt local config used to fail silently (every
# python helper below has its own `except: <default>` fallback), so a typo in
# journal-config.json would silently revert every knob to its default with no
# signal. Validate once, loudly: if the local config exists but is not valid
# JSON, print the error to stderr. On a manual run we abort (exit 2) so the user
# notices; on a hook-sourced run we must not block the session, so we log the
# breakage and continue on the shipped defaults.
if [[ -f "$LOCAL_CONFIG" ]]; then
	if ! cfg_err="$(python3 -c '
import json,sys
try:
    json.load(open(sys.argv[1]))
except Exception as e:
    print(e); sys.exit(1)
' "$LOCAL_CONFIG" 2>&1)"; then
		echo "session-journal: local config is not valid JSON — $cfg_err" >&2
		echo "  file: $LOCAL_CONFIG" >&2
		echo "  fix the JSON, or delete it to fall back to $DEFAULT_CONFIG" >&2
		if [[ "$source_label" == "manual" ]]; then
			exit 2
		fi
		# Hook path: do not block the session — fall back to the default config
		# but record that we did so.
		echo "session-journal: falling back to default config (hook must not block)" >&2
		config_path="$DEFAULT_CONFIG"
	fi
fi

# Resolve transcript_path from stdin payload if requested.
if [[ "$from_stdin" -eq 1 ]]; then
	payload="$(cat || true)"
	if [[ -n "$payload" ]]; then
		transcript_path="$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get("transcript_path",""))
except Exception:
    print("")
' 2>/dev/null || true)"
	fi
fi

# Optional logging.
log() {
	local enabled
	enabled="$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print('1' if c.get('general',{}).get('log_enabled', True) else '0')
except Exception:
    print('1')
" 2>/dev/null || echo 1)"
	[[ "$enabled" != "1" ]] && return 0
	local log_rel
	log_rel="$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print(c.get('general',{}).get('log_path','local/sessions/.journal-hook.log'))
except Exception:
    print('local/sessions/.journal-hook.log')
" 2>/dev/null || echo 'local/sessions/.journal-hook.log')"
	mkdir -p "$(dirname "$BRAIN_ROOT/$log_rel")"
	printf '[%s] %s %s\n' "$(date -u +%FT%TZ)" "$source_label" "$*" >>"$BRAIN_ROOT/$log_rel"
}

# Check master switch.
enabled="$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print('1' if c.get('enabled', True) else '0')
except Exception:
    print('1')
" 2>/dev/null || echo 1)"
if [[ "$enabled" != "1" ]]; then
	log "skipped (addon disabled)"
	exit 0
fi

# Per-source enable.
if [[ "$source_label" == "stop" ]]; then
	stop_on="$(python3 -c "
import json
c = json.load(open('$config_path'))
print('1' if c.get('stop_hook',{}).get('enabled',True) else '0')
" 2>/dev/null || echo 1)"
	[[ "$stop_on" != "1" ]] && { log "skipped (stop_hook disabled)"; exit 0; }
fi

if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
	log "no transcript path ($transcript_path); writing minimal update"
fi

mkdir -p "$(dirname "$JOURNAL")"

# Heavy lifting: parse + rewrite in one python3 call.
python3 - "$config_path" "$JOURNAL" "$transcript_path" "$source_label" <<'PYEOF'
import json, os, sys, re
from datetime import datetime
from pathlib import Path

cfg_path, journal_path, transcript_path, source = sys.argv[1:5]

with open(cfg_path) as f:
    cfg = json.load(f)

stop_cfg = cfg.get("stop_hook", {})
gen_cfg  = cfg.get("general", {})
max_files = int(stop_cfg.get("max_files", 25))
max_chars = int(stop_cfg.get("max_message_chars", 280))
max_lines = int(gen_cfg.get("transcript_max_lines", 1500))

include_files     = bool(stop_cfg.get("include_files", True))
include_tasks     = bool(stop_cfg.get("include_tasks", True))
include_last_user = bool(stop_cfg.get("include_last_user_message", True))
include_last_asst = bool(stop_cfg.get("include_last_assistant_message", True))

# ---- Parse transcript (best-effort, tolerant) ----
cwd = ""
last_user_text = ""
last_assistant_text = ""
file_events = []          # list of (path, op)
task_subjects = {}        # subject -> status, last seen
seen_files = set()

def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                t = b.get("text","")
                if t: parts.append(t)
        return "\n".join(parts)
    return ""

if transcript_path and os.path.isfile(transcript_path):
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        # Window to last N lines to keep parsing fast for long sessions.
        if len(lines) > max_lines:
            lines = lines[-max_lines:]
        for line in lines:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("cwd"):
                cwd = d["cwd"]
            t = d.get("type")
            msg = d.get("message", {}) if isinstance(d.get("message"), dict) else {}
            content = msg.get("content")

            if t == "user":
                # Tool results are also type=user with content list of tool_result. Skip those.
                txt = extract_text(content)
                # Heuristic: real user text is non-empty after stripping system reminders.
                if txt and not txt.startswith("<system-reminder>") and "tool_result" not in (
                    content[0].get("type","") if isinstance(content,list) and content and isinstance(content[0],dict) else ""
                ):
                    # Strip leading system-reminder blocks if present.
                    clean = re.sub(r"<system-reminder>.*?</system-reminder>", "", txt, flags=re.S).strip()
                    if clean:
                        last_user_text = clean

            elif t == "assistant" and isinstance(content, list):
                # Collect tool_use blocks and last text block.
                txt_parts = []
                for b in content:
                    if not isinstance(b, dict): continue
                    btype = b.get("type")
                    if btype == "text":
                        if b.get("text"): txt_parts.append(b["text"])
                    elif btype == "tool_use":
                        name = b.get("name","")
                        inp = b.get("input", {}) or {}
                        if name in ("Edit","Write","MultiEdit","NotebookEdit"):
                            fp = inp.get("file_path") or inp.get("notebook_path") or ""
                            if fp and fp not in seen_files:
                                seen_files.add(fp)
                                file_events.append((fp, name))
                        elif name == "TaskCreate":
                            subj = inp.get("subject","")
                            if subj: task_subjects.setdefault(subj, "pending")
                        elif name == "TaskUpdate":
                            # We don't have subject directly; carries taskId. Best-effort: skip.
                            pass
                if txt_parts:
                    last_assistant_text = "\n".join(txt_parts).strip()
    except Exception as e:
        last_assistant_text = last_assistant_text or ""
        # Don't crash the hook on parse errors.

# ---- Build journal content ----
project_name = ""
project_mode = gen_cfg.get("project_inference", "cwd_basename")
if cwd:
    if project_mode == "cwd_basename":
        project_name = os.path.basename(cwd.rstrip("/"))
    else:
        project_name = cwd

def truncate(s, n):
    s = s.strip()
    if len(s) <= n: return s
    return s[:n].rstrip() + "…"

# Heuristic Task summary = first line of last user message.
task_line = ""
if include_last_user and last_user_text:
    first_line = last_user_text.splitlines()[0]
    task_line = truncate(first_line, max_chars)

# Files (cap to max_files).
files_block_lines = []
if include_files and file_events:
    for fp, op in file_events[-max_files:]:
        # Relative path if inside cwd.
        rel = fp
        if cwd and fp.startswith(cwd):
            rel = fp[len(cwd):].lstrip("/")
        files_block_lines.append(f"- `{rel}` — {op}")

# Tasks discovered (just subjects we saw; we don't reliably know status from transcript).
tasks_block_lines = []
if include_tasks and task_subjects:
    for subj in list(task_subjects)[-15:]:
        tasks_block_lines.append(f"- [ ] {truncate(subj, 120)}")

# Next step hint: last assistant text trimmed.
next_step = ""
if include_last_asst and last_assistant_text:
    # Drop trailing tool-call narration; take first sentence-ish.
    clean = re.sub(r"\n+", " ", last_assistant_text).strip()
    next_step = truncate(clean, max_chars)

# ---- Frontmatter handling ----
date_str = datetime.now().strftime("%Y-%m-%d")
time_str = datetime.now().strftime("%H:%M")

fm_id = ""
fm_previous = ""
fm_status = "active"

if os.path.isfile(journal_path):
    try:
        existing = open(journal_path).read()
        m = re.match(r"^---\n(.*?)\n---\n", existing, re.S)
        if m:
            fm = m.group(1)
            for key in ("id","previous","status"):
                km = re.search(rf"^{key}:\s*(.+)$", fm, re.M)
                if km:
                    val = km.group(1).strip()
                    if key == "id": fm_id = val
                    elif key == "previous": fm_previous = val
                    elif key == "status": fm_status = val
    except Exception:
        pass

# If id missing, generate a placeholder; uuid5-gen.sh would be ideal but session-start owns id.
# Leave empty if we have no previous id — the session-start flow sets it.
fm_lines = ["---",
            f"date: {date_str}",
            "type: session-journal",
            "tags: [session]",
            f"project: {project_name}",
            f"previous: {fm_previous}",
            f"id: {fm_id}",
            f"status: {fm_status}",
            "---"]

body = [
    "",
    "# Session Journal",
    "",
    f"## Last updated: {time_str} (auto: {source})",
    "",
    f"### Project: {project_name}",
    f"### Task: {task_line}",
    "",
    "### Done",
]
if tasks_block_lines:
    body.extend(tasks_block_lines)
else:
    body.append("- ")
body.extend(["", "### Files changed"])
if files_block_lines:
    body.extend(files_block_lines)
else:
    body.append("- ")
body.extend(["", "### Next step", f"-> {next_step}" if next_step else "-> ", ""])
body.extend(["### Open questions", "- ", ""])

out = "\n".join(fm_lines) + "\n" + "\n".join(body)

# Atomic write.
tmp = journal_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(out)
os.replace(tmp, journal_path)

# Touch mtime so throttling works from this moment.
os.utime(journal_path, None)

print(f"journal updated: project='{project_name}' files={len(files_block_lines)} tasks={len(tasks_block_lines)}", file=sys.stderr)
PYEOF

log "updated journal ($JOURNAL)"
exit 0
