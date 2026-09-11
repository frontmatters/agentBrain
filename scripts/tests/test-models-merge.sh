#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-models-merge.sh — merging the brain's model fragment into Pi must never
# take anything away.
#
# configure-pi.sh carries the private fragment vault/pi-config/models.json into
# ~/.pi/agent/models.json. The contract is a provider-level upsert: a provider
# already configured on this machine keeps its LOCAL definition, providers the
# machine lacks are added, and nothing is ever removed. That is easy to state
# and easy to break: one json.dump of the merged dict in the wrong direction
# silently replaces a machine's working endpoint with the brain's.
#
# Sources configure-pi.sh (main-guarded, so nothing runs on source) and drives
# merge_models_json against throwaway directories.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

# Named t_ok/t_bad, not ok/bad: this file sources configure-pi.sh, which
# defines its own ok() for user-facing output. An earlier version used the
# plain names, the source silently replaced them, and every assertion printed
# a green tick while the counters stayed at zero. The suite reported
# "0 passed, 0 failed" and exited 0, so it passed without asserting anything.
pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-models-merge.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=../configure-pi.sh
source "$ROOT_DIR/scripts/configure-pi.sh" >/dev/null 2>&1

PI_SRC="$TMP/brain"
PI_CONFIG_DIR="$TMP/pi"
mkdir -p "$PI_SRC/vault/pi-config" "$PI_CONFIG_DIR"

frag()  { printf '%s\n' "$1" > "$PI_SRC/vault/pi-config/models.json"; }
dest()  { printf '%s\n' "$1" > "$PI_CONFIG_DIR/models.json"; }
field() { python3 -c "
import json,sys
d=json.load(open('$PI_CONFIG_DIR/models.json'))
print(d['providers'].get(sys.argv[1],{}).get('baseUrl',''))" "$1"; }

# --- 1. no fragment is a no-op, not an error --------------------------------
dest '{"providers":{"local":{"baseUrl":"http://machine"}}}'
merge_models_json >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && [ "$(field local)" = "http://machine" ] \
	&& t_ok "no fragment leaves the machine's models.json alone" \
	|| t_bad "a missing fragment disturbed models.json (rc=$rc)"

# --- 2. no destination: the fragment is installed, owner-only ---------------
# It can carry endpoints and keys, so it must not be world readable.
rm -f "$PI_CONFIG_DIR/models.json"
frag '{"providers":{"brainOnly":{"baseUrl":"http://brain"}}}'
merge_models_json >/dev/null 2>&1
if [ "$(field brainOnly)" = "http://brain" ]; then
	mode="$(stat -f '%Lp' "$PI_CONFIG_DIR/models.json" 2>/dev/null || stat -c '%a' "$PI_CONFIG_DIR/models.json")"
	t_ok "a first install copies the fragment"
	[ "$mode" = "600" ] && t_ok "the copy is owner-only (600)" || t_bad "expected mode 600, got $mode"
else
	t_bad "a first install did not copy the fragment"
fi

# --- 3. the machine wins, the brain fills the gaps, nothing is lost ---------
# This is the whole contract in one assertion.
dest '{"providers":{"shared":{"baseUrl":"http://machine"},"onlyHere":{"baseUrl":"http://keep"}}}'
frag '{"providers":{"shared":{"baseUrl":"http://brain"},"onlyBrain":{"baseUrl":"http://added"}}}'
merge_models_json >/dev/null 2>&1
[ "$(field shared)"   = "http://machine" ] && t_ok "a provider on this machine keeps its local definition" || t_bad "the brain overwrote a local provider"
[ "$(field onlyBrain)" = "http://added"  ] && t_ok "a provider missing here is added"                      || t_bad "a brain-only provider was not added"
[ "$(field onlyHere)"  = "http://keep"   ] && t_ok "a provider only this machine has survives"             || t_bad "a machine-only provider was deleted"

# --- 4. unrelated top-level keys survive ------------------------------------
# The merge touches "providers". Anything else in the file is the machine's.
dest '{"defaultModel":"mine","providers":{"a":{"baseUrl":"http://a"}}}'
frag '{"providers":{"b":{"baseUrl":"http://b"}}}'
merge_models_json >/dev/null 2>&1
[ "$(python3 -c "import json;print(json.load(open('$PI_CONFIG_DIR/models.json')).get('defaultModel',''))")" = "mine" ] \
	&& t_ok "unrelated top-level keys are preserved" \
	|| t_bad "the merge dropped a top-level key it does not own"

# --- 5. invalid JSON leaves the file untouched ------------------------------
# The dangerous failure is a half-written file, not a warning.
dest '{"providers":{"safe":{"baseUrl":"http://safe"}}}'
before="$(shasum -a 256 "$PI_CONFIG_DIR/models.json" | cut -d' ' -f1)"
frag '{ this is not json'
merge_models_json >/dev/null 2>&1
after="$(shasum -a 256 "$PI_CONFIG_DIR/models.json" | cut -d' ' -f1)"
[ "$before" = "$after" ] \
	&& t_ok "an invalid fragment leaves models.json byte-identical" \
	|| t_bad "an invalid fragment modified models.json"

# A suite that asserted nothing must not report success. This exact file
# already did that once, so the guard is not hypothetical.
if [ "$((pass + fail))" -lt 8 ]; then
	printf 'models-merge: only %d assertion(s) ran, expected at least 8\n' "$((pass + fail))" >&2
	exit 1
fi
printf 'models-merge: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
