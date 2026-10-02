#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# active-space.sh — DEPRECATED session mode for spaces.
#
# The vault-global local/.active-space marker is decommissioned: it married
# work-context to storage and leaked across parallel sessions. Nothing reads it
# anymore:
#   - note WRITES infer context per-write (new-note.sh → system/lib/context.sh)
#   - MCP recall (brain_search / brain_recent) reads AGENTBRAIN_CONTEXT (env) only
# Set the per-session context via AGENTBRAIN_CONTEXT=<slug> (or `new-note --context
# <slug>`). This shim keeps use/show/clear round-tripping for backward-compat, but
# the marker has NO effect on writes or recall.
#
# The compatibility marker is gitignored in the active vault: vault/.active-space.
#
# Usage:
#   active-space.sh use <slug>    activate a space (must exist; slug path-guarded)
#   active-space.sh clear         deactivate (remove the marker)
#   active-space.sh show          print the active slug, or "none"  (default)
#   active-space.sh resolve       machine-readable: raw slug, or empty (no "none")
#
# This shim's show/resolve commands use AGENTBRAIN_SPACE, then the marker,
# then empty. Neither writes nor MCP recall consult this legacy resolver.
#
# Sourceable: `source active-space.sh` defines active_space_slug() (the resolver)
# without running any subcommand, for scripts that prefer an in-process call.
set -euo pipefail

# Brain root from this script's own location (works in worktrees and via the alias).
_active_space_root() {
	cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd
}
# shellcheck source=scripts/lib/vault.sh
. "$(_active_space_root)/scripts/lib/vault.sh"

# Slug guard — identical policy to new-note.sh's --space: an empty slug or one
# containing '/', '..', a leading dot, or any char outside [a-z0-9._-] could
# escape vault/spaces/<slug>/, defeating the seal.
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
	marker="$VAULT_DIR/.active-space"
	if [ -f "$marker" ]; then
		head -n1 "$marker" | tr -d '[:space:]'
	fi
}

# Subcommands run only on direct execution; sourcing just loads the resolver.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	MARKER="$VAULT_DIR/.active-space"
	cmd="${1:-show}"
	case "$cmd" in
		use)
			slug="${2:-}"
			if ! _active_space_valid "$slug"; then
				echo "active-space: invalid slug: '$slug' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')" >&2
				exit 2
			fi
			if [ ! -d "$VAULT_DIR/spaces/$slug" ]; then
				echo "active-space: space does not exist: vault/spaces/$slug" >&2
				exit 1
			fi
			mkdir -p "$(dirname "$MARKER")"
			printf '%s\n' "$slug" >"$MARKER"
			echo "active space: $slug"
			echo "DEPRECATED: the .active-space marker no longer affects writes OR recall." >&2
			echo "            Set AGENTBRAIN_CONTEXT=$slug for this session instead." >&2
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
