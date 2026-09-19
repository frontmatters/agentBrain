#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-agent-pointers.sh — do the paths handed to each agent still exist?
#
# Every agent gets a pointer block naming the files to read at session start. The setup
# scripts append that block and then skip when one is already there, so they verify that a
# block EXISTS and never that it still POINTS somewhere. When vault/ replaced local/, one
# agent's block was updated and another's was not, and nobody noticed: a missing file is
# silent. No error, no warning, simply no knowledge (found 2026-09-16, 6 of 10 dead).
#
# Absence is allowed where the instruction says so: a line reading "any existing files
# under" describes an optional directory, not a broken pointer.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fouten=0; gecontroleerd=0

controleer() {  # $1 = label, $2 = bestand met verwijzingen
	local label="$1" bestand="$2"
	[ -f "$bestand" ] || return 0
	local regel pad
	while IFS= read -r regel; do
		case "$regel" in *"any existing files under"*) continue ;; esac
		while read -r pad; do
			[ -n "$pad" ] || continue
			gecontroleerd=$((gecontroleerd + 1))
			if [ ! -e "$pad" ]; then
				echo "  ${label}: verwijst naar iets dat niet bestaat — ${pad#"${AGENTBRAIN_HOME:-$HOME}"/}" >&2
				fouten=$((fouten + 1))
			fi
		done < <(printf '%s\n' "$regel" | grep -oE "${ROOT}/[A-Za-z0-9/._-]+" || true)
	done < "$bestand"
}

controleer "Claude Code" "${AGENTBRAIN_HOME:-$HOME}/.claude/CLAUDE.md"
controleer "Copilot CLI" "${AGENTBRAIN_HOME:-$HOME}/.copilot/copilot-instructions.md"
controleer "Pi" "$ROOT/system/pi-config/agents.md"

if [ "$fouten" -gt 0 ]; then
	echo "check-agent-pointers: $fouten dode verwijzing(en) van $gecontroleerd" >&2
	exit 1
fi
echo "check-agent-pointers: ok ($gecontroleerd verwijzing(en), alle bestaand)"
