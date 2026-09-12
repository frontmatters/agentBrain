#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# sandbox-run.sh — run a command against a throwaway agentBrain, never yours.
#
#   bash scripts/tools/sandbox-run.sh bash scripts/setup/setup-default-addons.sh
#   bash scripts/tools/sandbox-run.sh --keep bash scripts/addons.sh enable shorthand
#
# Testing anything that touches agents needs FIVE variables set together, and
# setting four of them is worse than setting none: the run looks isolated and
# is not. Enabling an add-on syncs agent skill links, and that sync PRUNES links
# whose add-on is missing from the state it was handed. Point ADDONS_STATE at a
# fixture and forget AGENTBRAIN_HOME, and the prune empties the real ~/.claude,
# ~/.copilot and ~/.pi. That happened on 2026-09-11, twice in one evening.
#
# The variables, and why each one matters:
#   AGENTBRAIN_HOME   where agent skill dirs are read and written
#   ADDONS_STATE      which add-ons count as enabled (addons.sh does NOT read
#                     AGENTBRAIN_HOME; its state is relative to the checkout)
#   PI_CONFIG_DIR     Pi's own skills, extensions and config
#   HOME              anything that reaches for ~ directly, git config included
#   PATH              system tools only, so the machine's own installs cannot
#                     leak in and make the run pass for the wrong reason
#
# The checkout stays read-only in practice: this redirects where things are
# written, it does not copy the framework. A command that writes INTO the
# checkout (a generated tsconfig, a regenerated index) still writes there, so
# check `git status` afterwards for anything gitignored.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
KEEP=0
[ "${1:-}" = "--keep" ] && { KEEP=1; shift; }
[ $# -gt 0 ] || { sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/ab-sandbox.XXXXXX")"
mkdir -p "$SB/ab-home" "$SB/addons-state" "$SB/pi"
printf '[user]\n\tname = Sandbox\n\temail = sandbox@example.invalid\n' > "$SB/ab-home/.gitconfig"

printf 'sandbox: %s\n' "$SB"
cd "$ROOT_DIR" || exit 1

HOME="$SB/ab-home" \
AGENTBRAIN_HOME="$SB/ab-home" \
ADDONS_STATE="$SB/addons-state" \
PI_CONFIG_DIR="$SB/pi" \
GIT_CEILING_DIRECTORIES="$SB" \
PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
	"$@"
rc=$?

# A failed run is the one you want to look at, so it is never swept away.
if [ "$rc" -ne 0 ] || [ "$KEEP" = 1 ]; then
	printf 'sandbox kept for inspection: %s (exit %d)\n' "$SB" "$rc"
else
	rm -rf "$SB"
fi

# The real agent dirs must be exactly as they were. This is the assertion the
# evening of 2026-09-11 was missing: the damage was invisible until the next
# doctor run, an hour later.
for d in "$HOME/.claude/skills" "$HOME/.copilot/skills" "$HOME/.pi/agent/skills"; do
	[ -d "$d" ] || continue
	printf '  untouched: %s (%d entries)\n' "${d/#$HOME/~}" "$(ls "$d" 2>/dev/null | wc -l | tr -d ' ')"
done
exit "$rc"
