#!/usr/bin/env bash
# Append a manual note to the current journal's "Open questions" section, or
# overwrite the Task line if --task is passed.
# Usage:
#   journal-save.sh "free text"          # appends to Open questions
#   journal-save.sh --task "task line"   # overwrites the Task: line
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
JOURNAL="$BRAIN_ROOT/local/sessions/session-journal.md"

mode="note"
text=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--task) mode="task"; text="$2"; shift 2 ;;
		--note) mode="note"; text="$2"; shift 2 ;;
		*) text="${text:+$text }$1"; shift ;;
	esac
done

if [[ -z "$text" ]]; then
	echo "usage: journal-save.sh [--task|--note] <text>" >&2
	exit 2
fi

mkdir -p "$(dirname "$JOURNAL")"
if [[ ! -f "$JOURNAL" ]]; then
	echo "no journal yet at $JOURNAL — run /journal or wait for the next hook" >&2
	exit 1
fi

python3 - "$JOURNAL" "$mode" "$text" <<'PYEOF'
import sys, re
path, mode, text = sys.argv[1:4]
content = open(path).read()
ts = __import__("datetime").datetime.now().strftime("%H:%M")

if mode == "task":
    content = re.sub(r"^### Task:.*$", f"### Task: {text}", content, count=1, flags=re.M)
else:
    # Append under "### Open questions"
    if re.search(r"^### Open questions", content, re.M):
        content = re.sub(
            r"(### Open questions\n)((?:- .*\n)*)",
            lambda m: m.group(1) + m.group(2) + f"- [{ts}] {text}\n",
            content, count=1, flags=re.M)
    else:
        content += f"\n### Open questions\n- [{ts}] {text}\n"

# Update Last updated marker
content = re.sub(r"^## Last updated:.*$",
                 f"## Last updated: {ts} (manual)",
                 content, count=1, flags=re.M)

open(path,"w").write(content)
print(f"journal saved ({mode}): {text[:80]}")
PYEOF
