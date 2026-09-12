#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# PostToolUse hook for mode=sync_hook.
# Detects writes (Write|Edit|MultiEdit) targeting ~/.claude/projects/*/memory/*.md
# and mirrors them into agentBrain with normalized frontmatter. Optionally deletes
# the original after successful sync. Always exits 0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/vault/memories/claude-redirect-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"
config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

payload="$(cat || true)"
[[ -z "$payload" ]] && exit 0

# Only act if mode=sync_hook AND addon enabled.
mode="$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print(c.get('mode','symlink') if c.get('enabled',True) else 'disabled')
except Exception:
    print('disabled')
" 2>/dev/null || echo disabled)"
[[ "$mode" != "sync_hook" ]] && exit 0

# Pull tool_name + file_path from the payload.
read -r tool_name fp <<<"$(printf '%s' "$payload" | python3 -c "
import json,sys
try:
    d = json.loads(sys.stdin.read())
    tn = d.get('tool_name','')
    ti = d.get('tool_input',{}) or {}
    print(tn, ti.get('file_path','') or ti.get('notebook_path',''))
except Exception:
    print('','')
" 2>/dev/null || echo " ")"

# Only memory-dir markdown writes.
case "$tool_name" in
	Write|Edit|MultiEdit|NotebookEdit) ;;
	*) exit 0 ;;
esac
[[ "$fp" != *"/.claude/projects/"*"/memory/"*".md" ]] && exit 0
[[ ! -f "$fp" ]] && exit 0

# Resolve the project dir; the migrate script derives the slug itself.
project_dir="${fp%/memory/*}"

# Delegate to the migrate script for the single file (it does normalization).
# We pass the project_dir; migrate only processes its memory dir.
(
	bash "$HERE/claude-memory-migrate.sh" "$project_dir" >/dev/null 2>&1
	# Optional delete-after-sync.
	delete="$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print('1' if c.get('sync_hook',{}).get('delete_original_after_sync',False) else '0')
except Exception:
    print('0')
" 2>/dev/null || echo 0)"
	if [[ "$delete" == "1" ]]; then
		rm -f "$fp"
	fi
) &
disown 2>/dev/null || true
exit 0
