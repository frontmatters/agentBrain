#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-sandbox-home.sh — code the doctor runs must read AGENTBRAIN_HOME, not $HOME.
#
# The release gate installs into a throwaway directory by exporting
# AGENTBRAIN_HOME and leaving HOME alone, because HOME still has to reach the
# machine's real tools (brew, gh, nvm). Every script that resolves agentBrain's
# own location or state therefore has to read ${AGENTBRAIN_HOME:-$HOME}. One
# that reads $HOME directly walks straight out of the sandbox.
#
# Found on 2026-09-13: test-park-system.sh resolved "$HOME/agentBrain", so the
# sandboxed doctor ran against the maintainer's live checkout and created a
# project and a learning in the real vault. Two publish gates refused, at two
# different steps, and neither was reproducible outside the gate: two runs were
# sharing one checkout. Nothing reported it, because from inside the test
# everything it touched existed.
#
# Tool locations are the exception and stay on $HOME: ~/.nvm, ~/.bun, ~/.local.
# A sandbox uses the machine's tools; only agentBrain's own state moves.
#
#   scripts/checks/check-sandbox-home.sh
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1

# The paths agentBrain itself owns. A tool's own dotdir is not in this list.
OWNED='agentBrain|\.agentBrain|\.claude|\.pi|\.copilot|\.gemini|Developer/agentBrain'
# $HOME reached directly. The sanctioned form ${AGENTBRAIN_HOME:-$HOME} contains
# the literal "$HOME}" too, so it is blanked out per line before matching rather
# than pattern-matched around: the first version of this check flagged all 28
# call sites including the ones it had just fixed, which is a check that cannot
# tell right from wrong dressed up as a finding.
OK_FORM='s|\${AGENTBRAIN_HOME:-\$HOME}|@AB_HOME@|g'
# Second arm, same concern: the state directory is .agentBrain, with the capital.
# setup-abh-autostart.sh wrote it in lower case, and on a case-insensitive volume
# that is one directory reachable under two names. git reports whichever name the
# entry carries, and sync-space refused to run on a MacBook Air because its guard
# compared the two spellings as strings. A launchd or systemd label
# (dev.agentbrain.loop, com.agentbrain.harness.web) is lower case by convention
# and is not a path, so only a leading slash counts.
RE="\\\$\\{?HOME\\}?/($OWNED)|/\\.agentbrain([/\"'\''[:space:]]|$)"

# Only what the doctor and the release gate execute. Installers and uninstallers
# legitimately address the invoking user's home.
SCOPE="scripts/checks scripts/tests scripts/selftest scripts/lib scripts/sync"

REG="$ROOT/scripts/lib/exemptions.tsv"
exempt() { # exempt <path>
	[ -f "$REG" ] || return 1
	local check pattern _expires _reason
	while IFS=$'\t' read -r check pattern _expires _reason; do
		[ "${check:-}" = "check-sandbox-home" ] || continue
		[ -n "${pattern:-}" ] || continue
		# The register holds globs, so the expansion is meant to glob here.
		# shellcheck disable=SC2254
		case "$1" in $pattern) return 0 ;; esac
	done < "$REG"
	return 1
}

fail=0
checked=0
exempted=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	# Counted before exempting: skipping first would let an exempted file vanish
	# from the denominator, and exempting the last file in scope would then read
	# as "nothing to examine" rather than as a pass.
	# This check and its negative twin quote the defect in order to describe it,
	# and counting them would also mean the denominator can never reach zero:
	# the empty-scope guard below would be unreachable, a vangnet that cannot
	# fire. Its own negative case caught that.
	case "$f" in */check-sandbox-home.sh) continue ;; esac
	checked=$((checked + 1))
	exempt "$f" && { exempted=$((exempted + 1)); continue; }
	# sed is line-preserving, so the line numbers still address the real file;
	# the original line is read back for the message.
	while IFS= read -r n; do
		[ -n "$n" ] || continue
		printf '  ✗ %s:%s:%s\n' "$f" "$n" "$(sed -n "${n}p" "$f" | sed 's/^[[:space:]]*//')"
		fail=1
	done < <(sed "$OK_FORM" "$f" | grep -nE "$RE" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | cut -d: -f1)
done < <(find $SCOPE -type f -name '*.sh' 2>/dev/null | sort)

# Never a verdict without a denominator: an empty scope would print a clean bill.
if [ "$checked" -eq 0 ]; then
	printf 'check-sandbox-home: no files in scope — has the layout moved?\n' >&2
	exit 1
fi

if [ "$fail" -ne 0 ]; then
	printf 'check-sandbox-home: $HOME read directly for a path agentBrain owns.\n' >&2
	printf '  Use ${AGENTBRAIN_HOME:-$HOME} so the release sandbox stays a sandbox.\n' >&2
	exit 1
fi
printf 'check-sandbox-home: ok (%d file(s), %d exempted; agentBrain paths go through AGENTBRAIN_HOME)\n' "$checked" "$exempted"
