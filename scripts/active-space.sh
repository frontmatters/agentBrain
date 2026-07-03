#!/usr/bin/env bash
# active-space.sh — "active space" session mode (incognito-style) for spaces.
#
# When a space is active, tooling operates INSIDE that space by default:
#   - new-note.sh (no --space) writes into the active space
#   - the agentbrain-mcp recall (brain_search / brain_recent) surfaces the active
#     space's notes while every OTHER space stays sealed
#
# State lives in a single gitignored marker in the active vault so it flips with
# `brain use dev|live` and is never synced:  local/.active-space
#
# Usage:
#   active-space.sh use <slug>    activate a space (must exist; slug path-guarded)
#   active-space.sh clear         deactivate (remove the marker)
#   active-space.sh show          print the active slug, or "none"  (default)
#   active-space.sh resolve       machine-readable: raw slug, or empty (no "none")
#
# Resolution order (used by show/resolve and by every consumer): the env var
# AGENTBRAIN_SPACE wins, else the marker, else empty. This mirrors how the MCP
# server resolves it (src/search.ts) so shell + TS never disagree.
#
# Sourceable: `source active-space.sh` defines active_space_slug() (the resolver)
# without running any subcommand, for scripts that prefer an in-process call.
set -euo pipefail

# Brain root from this script's own location (works in worktrees and via the alias).
_active_space_root() {
	cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Slug guard — identical policy to new-note.sh's --space: an empty slug or one
# containing '/', '..', a leading dot, or any char outside [a-z0-9._-] could
# escape local/spaces/<slug>/, defeating the seal.
_active_space_valid() {
	case "$1" in
		*[!a-z0-9._-]* | "" | .* | *..*) return 1 ;;
	esac
	return 0
}

# active_space_slug — echo the active space slug (env > marker > empty).
# The canonical resolver; safe to source and call from other scripts.
active_space_slug() {
	if [ -n "${AGENTBRAIN_SPACE:-}" ]; then
		printf '%s' "$AGENTBRAIN_SPACE"
		return 0
	fi
	local marker
	marker="$(_active_space_root)/local/.active-space"
	if [ -f "$marker" ]; then
		head -n1 "$marker" | tr -d '[:space:]'
	fi
}

# Subcommands run only on direct execution; sourcing just loads the resolver.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	ROOT="$(_active_space_root)"
	MARKER="$ROOT/local/.active-space"
	cmd="${1:-show}"
	case "$cmd" in
		use)
			slug="${2:-}"
			if ! _active_space_valid "$slug"; then
				echo "active-space: invalid slug: '$slug' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')" >&2
				exit 2
			fi
			if [ ! -d "$ROOT/local/spaces/$slug" ]; then
				echo "active-space: space does not exist: local/spaces/$slug" >&2
				exit 1
			fi
			mkdir -p "$(dirname "$MARKER")"
			printf '%s\n' "$slug" >"$MARKER"
			echo "active space: $slug"
			;;
		clear)
			rm -f "$MARKER"
			echo "active space: cleared"
			;;
		show | "")
			s="$(active_space_slug)"
			if [ -n "$s" ]; then echo "$s"; else echo "none"; fi
			;;
		resolve)
			active_space_slug
			;;
		*)
			echo "usage: active-space.sh [use <slug>|clear|show|resolve]" >&2
			exit 2
			;;
	esac
fi
