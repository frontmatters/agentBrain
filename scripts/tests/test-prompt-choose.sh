#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-prompt-choose.sh — a menu must return meaning, not a position.
#
# Three call sites read ab_prompt_select's index as one-based when it is
# zero-based, in three different files: choosing the first editor picked the
# last one, choosing "neither" installed VSCodium, and choosing "keep" disabled
# login autostart. Same shape every time, so the fix is a helper that never
# hands a position to a caller.
#
# ab_prompt_select is driven here with a stub, because the real one reads a tty.
# What is under test is the mapping, which is where every one of those bugs was.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

# shellcheck source=../installer/prompt-helper.sh
. "$ROOT_DIR/scripts/installer/prompt-helper.sh"

# Stub: answer with the row the test wants, in the zero-based form the real
# helper uses. PICK is one-based, like what a user presses.
ab_prompt_select() {
	local dflt=1
	while :; do case "${1:-}" in --default) dflt="$2"; shift 2 ;; *) break ;; esac; done
	shift                      # title
	[ "${PICK:-}" = "cancel" ] && return 1
	local n="${PICK:-$dflt}"
	LAST_DEFAULT="$dflt"       # so a test can assert where the cursor started
	REPLY=$((n - 1))
	return 0
}

choose() { ab_prompt_choose "$@"; }

# --- 1. the first option returns the first id -------------------------------
# This is the exact bug: the first option yielded index 0, which the caller read
# as "no match" and treated as a decline.
PICK=1 choose "Pick" a "Option A" b "Option B" c "Option C"
[ "$REPLY_ID" = a ] && t_ok "the first option returns its own id" || t_bad "first option returned '$REPLY_ID', expected a"

# --- 2. the last option returns the last id ---------------------------------
# The other half: the last option used to fall through to the one before it.
PICK=3 choose "Pick" a "Option A" b "Option B" c "Option C"
[ "$REPLY_ID" = c ] && t_ok "the last option returns its own id" || t_bad "last option returned '$REPLY_ID', expected c"

PICK=2 choose "Pick" a "Option A" b "Option B" c "Option C"
[ "$REPLY_ID" = b ] && t_ok "a middle option returns its own id" || t_bad "middle option returned '$REPLY_ID', expected b"

# --- 3. --default names an id, not a row --------------------------------------
# A row number goes stale when an option is added or hidden on a platform; an id
# does not. The editor menu hides VS Code where there is no recipe for it.
PICK="" choose --default c "Pick" a "A" b "B" c "C"
[ "$REPLY_ID" = c ] && t_ok "the default is found by id" || t_bad "default by id returned '$REPLY_ID'"
[ "${LAST_DEFAULT:-}" = 3 ] && t_ok "the cursor starts on the default row" || t_bad "cursor started on row ${LAST_DEFAULT:-?}, expected 3"

# The same call with the first option absent still defaults to c, now row 2.
PICK="" choose --default c "Pick" b "B" c "C"
[ "$REPLY_ID" = c ] && [ "${LAST_DEFAULT:-}" = 2 ] \
	&& t_ok "the default follows its id when an option is absent" \
	|| t_bad "default moved with the rows: id=$REPLY_ID row=${LAST_DEFAULT:-?}"

# --- 4. cancelling reports cancelled, and leaves no stale id ------------------
REPLY_ID="leftover"
PICK=cancel choose "Pick" a "A" b "B" && t_bad "cancel reported success" || t_ok "cancel returns non-zero"
[ -z "$REPLY_ID" ] && t_ok "cancel leaves no stale id" || t_bad "cancel left REPLY_ID='$REPLY_ID'"

# --- 5. no pairs is a usage error, not a silent pick -------------------------
choose "Pick"; rc=$?
[ "$rc" = 2 ] && t_ok "an empty menu is a usage error" || t_bad "empty menu returned $rc"

if [ "$((pass + fail))" -lt 9 ]; then
	printf 'prompt-choose: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'prompt-choose: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
