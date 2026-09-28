#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-agent-pointers.sh — do the paths handed to each agent still exist?
#
# Every agent gets a pointer block naming the files to read at session start. The setup
# scripts append that block and then skip when one is already there, so they verify that a
# block EXISTS and never that it still POINTS somewhere. After a path is renamed, a block
# that was not updated fails silently: no error, no warning, simply no knowledge.
#
# Absence is allowed where the instruction says so: a line reading "any existing files
# under" describes an optional directory, not a broken pointer.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0; checked=0

check_file() {  # $1 = label, $2 = file containing pointers
	local label="$1" file="$2"
	[ -f "$file" ] || return 0
	local line path
	while IFS= read -r line; do
		case "$line" in *"any existing files under"*) continue ;; esac
		while read -r path; do
			[ -n "$path" ] || continue
			checked=$((checked + 1))
			if [ ! -e "$path" ]; then
				echo "  ${label}: points to something that does not exist: ${path#"${AGENTBRAIN_HOME:-$HOME}"/}" >&2
				errors=$((errors + 1))
			fi
		done < <(printf '%s\n' "$line" | grep -oE "${ROOT}/[A-Za-z0-9/._-]+" || true)
	done < "$file"
}

check_file "Claude Code" "${AGENTBRAIN_HOME:-$HOME}/.claude/CLAUDE.md"
check_file "Copilot CLI" "${AGENTBRAIN_HOME:-$HOME}/.copilot/copilot-instructions.md"
check_file "Pi" "$ROOT/system/pi-config/agents.md"

if [ "$errors" -gt 0 ]; then
	echo "check-agent-pointers: $errors dead pointer(s) out of $checked" >&2
	exit 1
fi
echo "check-agent-pointers: ok ($checked pointer(s), all present)"
