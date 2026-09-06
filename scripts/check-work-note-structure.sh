#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-work-note-structure.sh — enforce the work-note content contract.
#
# MECHANISM ONLY. All values live in config, not here (agentBrain base principle,
# system/principles.md):
#   - the field contract (which sections/fields, tier, detector regex) -> system/work-note-contract.tsv
#   - the cutover date and the scope types                             -> system/ratchets.tsv
#   - the phase-in verdict (enforce/warn/exempt)                       -> scripts/lib/grandfather.sh
# To change what a work note must contain, edit the TSV. To move the cutover, edit
# the registry. This script never needs to change for either.
#
# Contract (system/work-note-contract.md): a work note MUST carry a problem, an
# acceptance definition and a status; it SHOULD carry owner, priority, dependencies
# and risks. Phased in with the grandfather clause: a MUST miss is a FAIL only for
# notes dated on/after the cutover; older notes and all SHOULD misses are WARN.
#
# Runs against the private layer (local/, a symlink to the vault); absent in CI, so
# skipped there. Exit 0 = no enforced failures. Exit 1 = one or more MUST failures.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/lib/grandfather.sh disable=SC1091
source "$ROOT_DIR/scripts/lib/grandfather.sh"

RULE="work-note-contract"
REGISTRY="$ROOT_DIR/system/ratchets.tsv"
CONTRACT="$ROOT_DIR/system/work-note-contract.tsv"
[ -f "$REGISTRY" ] && [ -f "$CONTRACT" ] || { echo "check-work-note-structure: missing config ($REGISTRY / $CONTRACT)" >&2; exit 1; }

CUTOVER="$(gf_cutover "$RULE" "$REGISTRY")"
TYPES="$(gf_registry_field "$RULE" 3 "$REGISTRY")"
[ -n "$CUTOVER" ] && [ -n "$TYPES" ] || { echo "check-work-note-structure: rule '$RULE' not in $REGISTRY" >&2; exit 1; }

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

# Load the field contract into parallel arrays (values come from the TSV, not here).
KEYS=(); TIERS=(); LABELS=(); REGEXES=()
while IFS=$'\t' read -r key tier _location label regex; do
	case "$key" in '' | \#*) continue ;; esac
	KEYS+=("$key"); TIERS+=("$tier"); LABELS+=("$label"); REGEXES+=("$regex")
done < "$CONTRACT"

# local/ is a symlink to the vault; resolve it so grep descends into it. Absent in CI.
LOCAL_DIR="$(cd local 2>/dev/null && pwd -P)" || { echo "check-work-note-structure: no vault/ layer (CI); skipped"; exit 0; }

WORKNOTES="$(grep -rIl --include='*.md' -E "^type: (${TYPES})\$" "$LOCAL_DIR" 2>/dev/null \
	| grep -viE '/(extracted|quarantine|graphify-out|\.trash|\.git|templates|legacy)/|youtube-digest' || true)"
[ -n "$WORKNOTES" ] || { echo "check-work-note-structure: no work notes found under vault/"; exit 0; }

errors=0
warns=0
notes_with_warn=0
# WARN lines are summarized by default; --verbose lists them, retrofit-work-notes.sh fixes them.
warn_line() { warns=$((warns + 1)); [ "$VERBOSE" = 1 ] && echo "WARN $1" >&2; return 0; }

while IFS= read -r f; do
	[ -f "$f" ] || continue
	verdict="$(gf_verdict "$f" "$CUTOVER")"
	[ "$verdict" = "exempt" ] && continue
	before=$warns

	i=0
	while [ "$i" -lt "${#KEYS[@]}" ]; do
		if ! grep -qiE "${REGEXES[$i]}" "$f"; then
			if [ "${TIERS[$i]}" = "MUST" ] && [ "$verdict" = "enforce" ]; then
				echo "FAIL $f: missing MUST '${LABELS[$i]}' (work-note-contract)" >&2
				errors=$((errors + 1))
			else
				warn_line "$f: missing ${TIERS[$i]} '${LABELS[$i]}'"
			fi
		fi
		i=$((i + 1))
	done

	[ "$warns" -gt "$before" ] && notes_with_warn=$((notes_with_warn + 1))
done <<< "$WORKNOTES"

summary="$warns warning(s) across $notes_with_warn note(s) (pre-cutover debt + SHOULD gaps; run --verbose or scripts/retrofit-work-notes.sh)"
if [ "$errors" -gt 0 ]; then
	echo "check-work-note-structure: $errors MUST failure(s) [blocking], $summary — see system/work-note-contract.md" >&2
	exit 1
fi
echo "check-work-note-structure: 0 MUST failures (grandfather cutover $CUTOVER); $summary"
