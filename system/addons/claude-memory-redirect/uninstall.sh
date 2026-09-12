#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# uninstall.sh — true inverse of install.sh for claude-memory-redirect.
#
# install.sh can do three things depending on mode: (1) replace each project's
# ~/.claude/projects/<encoded>/memory dir with a symlink into agentBrain, backing
# up the original; (2) register a PostToolUse sync hook in ~/.claude/settings.json;
# (3) leave a CLAUDE.md instruction block. This reverses all of them.
#
#   bash uninstall.sh                 # remove our symlinks + sync hook; keep agentBrain copies
#   bash uninstall.sh --restore       # also restore the newest pre-redirect backup over each link
#   bash uninstall.sh --purge         # also delete local config + redirect log
#   (flags combine: --restore --purge)
#
# Symlinks point INTO agentBrain, so simply removing them never deletes your
# migrated memory. --restore is only needed if you want Claude's original
# per-project memory dirs back in place. Idempotent; safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/vault/memories/claude-redirect-config.json"
LOG_FILE="$BRAIN_ROOT/vault/memories/.claude-redirect.log"
SETTINGS="$HOME/.claude/settings.json"
PROJECTS_ROOT="$HOME/.claude/projects"

RESTORE=0
PURGE=0
for arg in "$@"; do
	case "$arg" in
		--restore) RESTORE=1 ;;
		--purge)   PURGE=1 ;;
		*) echo "unknown flag: $arg (use --restore and/or --purge)" >&2; exit 2 ;;
	esac
done

links_removed=0
restored=0

# 1. Undo symlinks. Only touch memory dirs that are symlinks pointing into the
#    agentBrain target_root — never a real Claude memory dir we didn't create.
target_rel="$(python3 -c "
import json,sys
for p in ('$LOCAL_CONFIG','$HERE/config.default.json'):
    try:
        print(json.load(open(p)).get('target_root','vault/memories/projects')); sys.exit(0)
    except Exception:
        continue
print('vault/memories/projects')
" 2>/dev/null || echo 'vault/memories/projects')"
target_rel="vault/${target_rel#local/}"; target_rel="${target_rel#vault/vault/}"   # an older config still says local/
target_abs="$BRAIN_ROOT/$target_rel"

if [[ -d "$PROJECTS_ROOT" ]]; then
	while IFS= read -r mem; do
		[[ -L "$mem" ]] || continue
		dest="$(readlink "$mem")"
		case "$dest" in
			"$target_abs"/*|"$target_abs")
				project_dir="$(dirname "$mem")"
				rm "$mem"
				links_removed=$((links_removed + 1))
				echo "✓ removed symlink: $mem → $dest"
				if [[ "$RESTORE" -eq 1 ]]; then
					# Newest pre-redirect backup for this project, if any.
					backup="$(find "$project_dir" -maxdepth 1 -type d -name '.memory-pre-redirect-backup-*' 2>/dev/null | sort | tail -1 || true)"
					if [[ -n "$backup" ]]; then
						mv "$backup" "$mem"
						restored=$((restored + 1))
						echo "  ↪ restored original from $backup"
					else
						echo "  • no pre-redirect backup found — left memory dir absent (your data is in $dest)"
					fi
				fi
				;;
			*)
				echo "• skipped $mem (symlink target is outside agentBrain: $dest)"
				;;
		esac
	done < <(find "$PROJECTS_ROOT" -mindepth 2 -maxdepth 2 -name memory 2>/dev/null)
else
	echo "• no $PROJECTS_ROOT — no symlinks to undo"
fi

# 2. Remove the PostToolUse sync hook from settings.json (if registered).
if [[ -f "$SETTINGS" ]]; then
	if grep -q 'claude-memory-sync-hook.sh' "$SETTINGS"; then
		if python3 - "$SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
MARKER = "claude-memory-sync-hook.sh"
def matches(h):
    return isinstance(h, dict) and MARKER in str(h.get("command", ""))
hooks = data.get("hooks")
removed = 0
if isinstance(hooks, dict):
    for event, groups in list(hooks.items()):
        if not isinstance(groups, list):
            continue
        new_groups = []
        for group in groups:
            cmds = group.get("hooks", []) if isinstance(group, dict) else []
            kept = [h for h in cmds if not matches(h)]
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
print(f"claude-memory-redirect: removed {removed} sync-hook entr{'y' if removed==1 else 'ies'}", file=sys.stderr)
PYEOF
		then
			echo "✓ removed sync hook from $SETTINGS"
		else
			echo "⚠️  could not patch $SETTINGS (invalid JSON?) — remove the claude-memory-sync-hook.sh line manually" >&2
			exit 1
		fi
	else
		echo "• no sync hook in $SETTINGS — nothing to remove"
	fi
else
	echo "• no $SETTINGS — nothing to remove"
fi

# 3. The CLAUDE.md instruction block is documentation; we leave it (removing user
#    edits to CLAUDE.md is out of scope). Note it so the user can drop it manually.
echo "• left the CLAUDE.md instruction block intact (remove the 'Memory — alleen via agentBrain' section by hand if desired)"

# 4. Optionally purge per-machine state.
if [[ "$PURGE" -eq 1 ]]; then
	for f in "$LOCAL_CONFIG" "$LOG_FILE"; do
		if [[ -f "$f" ]]; then
			rm -f "$f"
			echo "✓ purged $f"
		fi
	done
	echo "• left migrated memory in $target_abs intact (never auto-deleted)"
else
	echo "• kept local config + migrated memory — use --purge to drop config/log"
fi

echo "claude-memory-redirect: uninstalled (links_removed=$links_removed restored=$restored)."
