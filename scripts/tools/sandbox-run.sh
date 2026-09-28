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
# ~/.copilot and ~/.pi.
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
[ $# -gt 0 ] || { sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# The real agent skill dirs a leaked prune would empty. Snapshotted before the
# run and compared after it, so damage is reported instead of assumed away.
REAL_HOME="$HOME"
PROTECTED=("$REAL_HOME/.claude/skills" "$REAL_HOME/.copilot/skills" "$REAL_HOME/.pi/agent/skills")

# snapshot <dir>: one line per entry, name and symlink target (or its type), so a
# pruned, added or re-pointed link all show up. Read-only; a missing dir is a
# state of its own, so a dir that appears or vanishes is a change too.
snapshot() {
	local d="$1" e
	[ -d "$d" ] || { echo "(absent)"; return 0; }
	for e in "$d"/* "$d"/.[!.]*; do
		[ -e "$e" ] || [ -L "$e" ] || continue
		if [ -L "$e" ]; then printf '%s -> %s\n' "${e##*/}" "$(readlink "$e")"
		elif [ -d "$e" ]; then printf '%s/\n' "${e##*/}"
		else printf '%s\n' "${e##*/}"
		fi
	done | LC_ALL=C sort
}

SB="$(mktemp -d "${TMPDIR:-/tmp}/ab-sandbox.XXXXXX")"
mkdir -p "$SB/before"
i=0
for d in "${PROTECTED[@]}"; do snapshot "$d" > "$SB/before/$i"; i=$((i + 1)); done
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

# The real agent dirs must be exactly as they were. Without this assertion the
# damage stays invisible until the next doctor run. A difference fails the run
# even when the command itself succeeded. Caveat: another session editing its
# skills at the same moment shows up here too; the diff says what moved.
changed=0
i=0
for d in "${PROTECTED[@]}"; do
	label="~${d#"$REAL_HOME"}"   # a literal ~: an unquoted one in ${d/#../~} expands back to $HOME
	if snapshot "$d" | diff "$SB/before/$i" - > "$SB/diff.$i"; then
		[ -d "$d" ] && printf '  untouched: %s (%d entries)\n' "$label" "$(grep -c . "$SB/before/$i")"
	else
		changed=1
		printf 'sandbox-run: CHANGED during the run: %s (< before, > after)\n' "$label" >&2
		sed 's/^/    /' "$SB/diff.$i" >&2
	fi
	i=$((i + 1))
done
if [ "$changed" = 1 ]; then
	echo "sandbox-run: the sandbox leaked into the real agent dirs above; restore them (bash scripts/brain.sh wire) and find the unset variable." >&2
	[ "$rc" -eq 0 ] && rc=1
fi

# A failed run is the one you want to look at, so it is never swept away.
if [ "$rc" -ne 0 ] || [ "$KEEP" = 1 ]; then
	printf 'sandbox kept for inspection: %s (exit %d)\n' "$SB" "$rc"
else
	rm -rf "$SB"
fi
exit "$rc"
