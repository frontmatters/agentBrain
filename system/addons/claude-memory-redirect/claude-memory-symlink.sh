#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Replace a Claude Code per-project memory directory with a symlink into agentBrain.
# Assumes claude-memory-migrate.sh has already moved content into the target.
# Usage:
#   claude-memory-symlink.sh                # current project only (derived from $PWD)
#   claude-memory-symlink.sh --all          # all projects
#   claude-memory-symlink.sh <project-dir>  # one specific project
#   claude-memory-symlink.sh --dry-run
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/vault/memories/claude-redirect-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"
config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

target_rel="$(python3 -c "
import json
c = json.load(open('$config_path'))
print(c.get('target_root','vault/memories/projects'))
" 2>/dev/null || echo "vault/memories/projects")"

backup="$(python3 -c "
import json
c = json.load(open('$config_path'))
print('1' if c.get('symlink',{}).get('backup_originals',True) else '0')
" 2>/dev/null || echo 1)"

dry_run=0
specific=""
all_projects=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) dry_run=1; shift ;;
		--all) all_projects=1; shift ;;
		*) specific="$1"; shift ;;
	esac
done

projects_root="$HOME/.claude/projects"

derive_current_project_dir() {
	local pwd_encoded
	pwd_encoded="$(printf '%s' "$PWD" | tr '/_ ' '---')"
	if [[ -d "$projects_root/$pwd_encoded" ]]; then
		printf '%s' "$projects_root/$pwd_encoded"
	fi
}

dirs=()
if [[ -n "$specific" ]]; then
	dirs+=("$specific")
elif [[ "$all_projects" -eq 1 ]]; then
	while IFS= read -r d; do
		dirs+=("$d")
	done < <(find "$projects_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
else
	current="$(derive_current_project_dir)"
	if [[ -z "$current" ]]; then
		echo "no Claude Code project dir for current cwd — pass dir or use --all" >&2
		exit 0
	fi
	dirs+=("$current")
fi

linked=0
already=0
backed_up=0

for project_dir in "${dirs[@]}"; do
	memory_dir="$project_dir/memory"

	if [[ -L "$memory_dir" ]]; then
		((already++)) || true
		continue
	fi

	# A dir without content is fine to replace with a symlink as long as target exists.
	slug="$(bash "$HERE/slug.sh" "$project_dir")"
	target_rel="vault/${target_rel#local/}"; target_rel="${target_rel#vault/vault/}"   # an older config still says local/
	target_dir="$BRAIN_ROOT/$target_rel/$slug"
	mkdir -p "$target_dir"

	if [[ "$dry_run" -eq 1 ]]; then
		echo "DRY: $memory_dir → $target_dir"
		continue
	fi

	# Backup original dir if it had content and config says so.
	if [[ -d "$memory_dir" ]]; then
		if [[ "$backup" == "1" ]] && [[ -n "$(ls -A "$memory_dir" 2>/dev/null)" ]]; then
			backup_dest="$project_dir/.memory-pre-redirect-backup-$(date +%Y%m%d-%H%M%S)"
			mv "$memory_dir" "$backup_dest"
			echo "  ↪ backed up original: $backup_dest"
			((backed_up++)) || true
		else
			rm -rf "$memory_dir"
		fi
	fi

	ln -s "$target_dir" "$memory_dir"
	echo "✓ symlinked: $memory_dir → $target_dir"
	((linked++)) || true
done

echo ""
echo "Total: linked=$linked already=$already backed_up=$backed_up"
[[ "$dry_run" -eq 1 ]] && echo "(dry run — no changes)"
exit 0
