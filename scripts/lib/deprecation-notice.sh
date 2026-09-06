#!/usr/bin/env bash
# deprecation-notice.sh — sourceable helper for RUNTIME deprecation of
# NON-frontmatter artifacts: CLI entrypoints, renamed subcommands, shell scripts.
#
# The frontmatter mechanism (`deprecated:` block + check-deprecations.sh) covers
# addons and skills. This covers the things that have no frontmatter to carry a
# block — the old entrypoint keeps working but prints one standardized line to
# stderr, the same shape `addons.sh status` / `skills list` use. It NEVER exits;
# the old path still runs. Silence with AGENTBRAIN_NO_DEPRECATION_NOTICE=1.
#
# Shape: deprecation_notice <old> [new] [remove_after] [reason]
#   - new empty        → "no replacement" (the discontinued case)
#   - remove_after set → appends "; removed after <date>"
#
# Usage — old shell entrypoint:
#   . "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/lib/deprecation-notice.sh"
#   deprecation_notice old-name new-name 2026-11-16 renamed
#   # ... old command keeps running ...
#
# Usage — one binary, old name reached via a symlink (detect from $0):
#   case "$(basename "$0")" in
#     old-name) deprecation_notice old-name new-name 2026-11-16 renamed ;;
#   esac
#
# Non-bash runtimes (bun/node/python): mirror this — print the same
# "⚠ '<old>' is deprecated (<reason>) → use '<new>'; removed after <date>" line to
# stderr and continue. Keep the wording identical for consistency.

deprecation_notice() {
	[ "${AGENTBRAIN_NO_DEPRECATION_NOTICE:-0}" = "1" ] && return 0
	local old="${1:?deprecation_notice: <old> required}" new="${2:-}" remove_after="${3:-}" reason="${4:-renamed}"
	local msg="⚠ '${old}' is deprecated (${reason})"
	if [ -n "$new" ]; then
		msg="${msg} → use '${new}'"
	fi
	if [ -n "$remove_after" ]; then
		msg="${msg}; removed after ${remove_after}"
	fi
	if [ -z "$new" ]; then
		msg="${msg} — no replacement"
	fi
	printf '%s\n' "$msg" >&2
}
