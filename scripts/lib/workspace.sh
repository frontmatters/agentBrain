#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# workspace.sh — resolve the workspace beside the vault.
#
# ~/.agentBrain/
#   vault/       what you learned      (git, own remote, doctor validates it)
#   shared/      what you share        (git, own remote)
#   workspace/   what you worked with  (no git, nothing validates it)
#
# The workspace exists because the vault holds its notes to a standard that
# working material cannot meet and should not be asked to. Anything a producer
# can rebuild, anything cloned from elsewhere, and anything thrown away next
# week belongs here instead of in local/.
#
# Three lanes, by lifetime rather than by subject:
#   external/<name>   third-party checkouts   — until you are done with them
#   derived/<name>    output of a producer    — until the producer runs again
#   scratch/<name>    throwaway working files — delete whenever
#
# Usage:  source "$ROOT/scripts/lib/workspace.sh"
#         out="$(workspace_dir derived graphify)"     # ensures it exists
#         root="$(workspace_root)"                    # creates nothing

# workspace_root — the workspace path. Always answers; may not exist yet.
workspace_root() {
	printf '%s' "${AGENTBRAIN_WORKSPACE:-${AGENTBRAIN_HOME:-$HOME}/.agentBrain/workspace}"
}

# workspace_dir <lane> <name> — the path, created. Prints it; empty on refusal.
workspace_dir() {
	local lane="$1" name="${2:-}" root
	case "$lane" in
	external | derived | scratch) ;;
	*)
		printf 'workspace_dir: unknown lane %s\n' "$lane" >&2
		return 1
		;;
	esac
	root="$(workspace_root)"
	local dir="$root/$lane${name:+/$name}"
	mkdir -p "$dir" || return 1
	printf '%s' "$dir"
}
