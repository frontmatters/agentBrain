#!/usr/bin/env bash
# uninstall.sh — true inverse of install.sh for session-journal.
# install.sh seeds local/sessions/journal-config.json and registers two Claude
# Code hooks (Stop + PostToolUse) in ~/.claude/settings.json. This removes any
# settings.json hook entry that points at this addon's hook scripts, and (only
# with --purge) the seeded local config and hook log.
#
#   bash uninstall.sh            # remove our hooks from settings.json; keep local config
#   bash uninstall.sh --purge    # also delete local config + hook log
#
# Idempotent: running it twice, or with no hooks installed, is a no-op (exit 0).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
LOCAL_CONFIG="$BRAIN_ROOT/local/sessions/journal-config.json"
LOG_FILE="$BRAIN_ROOT/local/sessions/.journal-hook.log"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

if [[ -f "$SETTINGS" ]]; then
	if grep -q 'session-journal/claude-stop-hook.sh\|session-journal/claude-autosave-hook.sh' "$SETTINGS"; then
		# Remove every hook command that references this addon. We rewrite the
		# JSON with python so we strip empty matcher groups too, rather than leave
		# dangling structure behind.
		if python3 - "$SETTINGS" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

MARKERS = ("session-journal/claude-stop-hook.sh",
           "session-journal/claude-autosave-hook.sh")

def cmd_matches(entry):
    return isinstance(entry, dict) and any(m in str(entry.get("command", "")) for m in MARKERS)

hooks = data.get("hooks")
removed = 0
if isinstance(hooks, dict):
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            continue
        new_groups = []
        for group in groups:
            cmds = group.get("hooks", []) if isinstance(group, dict) else []
            kept = [h for h in cmds if not cmd_matches(h)]
            removed += len(cmds) - len(kept)
            if kept:
                group["hooks"] = kept
                new_groups.append(group)
            elif not isinstance(group, dict) or "hooks" not in group:
                new_groups.append(group)
        if new_groups:
            hooks[event] = new_groups
        else:
            del hooks[event]
    if not hooks:
        del data["hooks"]

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"session-journal: removed {removed} hook entr{'y' if removed == 1 else 'ies'} from {path}", file=sys.stderr)
PYEOF
		then
			echo "✓ removed session-journal hooks from $SETTINGS"
		else
			echo "⚠️  could not patch $SETTINGS (invalid JSON?) — remove the session-journal hook lines manually" >&2
			exit 1
		fi
	else
		echo "• no session-journal hooks in $SETTINGS — nothing to remove"
	fi
else
	echo "• no $SETTINGS — nothing to remove"
fi

if [ "$PURGE" = "1" ]; then
	for f in "$LOCAL_CONFIG" "$LOG_FILE"; do
		if [ -f "$f" ]; then
			rm -f "$f"
			echo "✓ purged $f"
		fi
	done
else
	echo "• kept local config ($LOCAL_CONFIG) — use --purge to remove it"
fi

echo "session-journal: uninstalled."
