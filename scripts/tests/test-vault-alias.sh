#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-vault-alias.sh — `vault/` is an alias for `local/`, and an id never
# depends on which of the two names the caller typed.
#
# This is the invariant that makes the alias safe to ship: every id in every
# existing vault was derived from the `local/` spelling, so `vault/` must hash
# to exactly the same value. If this test fails, adopting the alias would
# silently fork note identity.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok()   { echo "  ok[$1]: $2"; }
bad()  { echo "  FAIL[$1]: $2" >&2; fail=1; }

# 1. Both spellings hash identically, at several depths.
for rel in "devices/gn100" "learnings/some-note" "spaces/a/projects/b/index" "x"; do
	a="$(bash "$ROOT/scripts/uuid5-gen.sh" "local/$rel")"
	b="$(bash "$ROOT/scripts/uuid5-gen.sh" "vault/$rel")"
	if [ -n "$a" ] && [ "$a" = "$b" ]; then
		ok "parity" "local/$rel == vault/$rel"
	else
		bad "parity" "local/$rel ($a) != vault/$rel ($b)"
	fi
done

# 2. Only a LEADING vault/ is rewritten — a nested one is a real path segment.
nested_a="$(bash "$ROOT/scripts/uuid5-gen.sh" "local/projects/vault/notes")"
nested_b="$(bash "$ROOT/scripts/uuid5-gen.sh" "local/projects/local/notes")"
if [ "$nested_a" != "$nested_b" ]; then
	ok "nested" "a nested 'vault' segment is left alone"
else
	bad "nested" "a nested 'vault' segment was rewritten"
fi

# 3. An unprefixed path is untouched (it is neither spelling).
bare="$(bash "$ROOT/scripts/uuid5-gen.sh" "devices/gn100")"
withl="$(bash "$ROOT/scripts/uuid5-gen.sh" "local/devices/gn100")"
if [ "$bare" != "$withl" ]; then
	ok "bare" "an unprefixed path still hashes on its own"
else
	bad "bare" "an unprefixed path collided with the local/ spelling"
fi

# 4. If the alias exists on this machine, it must point at local/ and resolve.
# Since 2026-09-05 vault/ is the real link and local/ the alias; before, the
# other way round. Either direction is fine as long as both name one directory.
if [ -L "$ROOT/vault" ] && [ -L "$ROOT/local" ]; then
	if [ "$(cd -P "$ROOT/vault" 2>/dev/null && pwd -P)" = "$(cd -P "$ROOT/local" 2>/dev/null && pwd -P)" ] && [ -d "$ROOT/vault" ]; then
		ok "link" "vault/ and local/ resolve to the same directory"
	else
		bad "link" "vault/ and local/ do not resolve to the same directory"
	fi
else
	ok "link" "no alias on this machine (optional): skipped"
fi

# 5. The id guard must recognise BOTH spellings. A guard that knows only one
# does not report a mismatch under the other — it reports nothing at all, which
# is how a rename silently switches the safety net off.
# The alias is made by setup; a checkout that never ran setup (a worktree, a
# fresh clone) has none, and without it the vault/ spelling names a path that
# does not exist, so the guard has nothing to check and the test reported the
# guard as silent. The property under test is the guard's parity, not whether
# this machine ran setup: make the alias for the duration when it is missing.
made_alias=0
if [ ! -e "$ROOT/vault" ] && ln -s local "$ROOT/vault" 2>/dev/null; then made_alias=1; fi
TMP="$ROOT/vault/devices/zz-test-vault-alias-$$.md"
if [ -d "$ROOT/vault/devices" ]; then
	# A note carrying an id that belongs to a different path: must be rejected.
	printf -- '---\ndate: 2026-01-01\ntype: reference\ntags: [test]\nid: 00000000-0000-5000-8000-000000000000\n---\n\n# t\n' > "$TMP"
	base="$(basename "$TMP")"
	via_local="$(bash "$ROOT/scripts/validate-note-id.sh" "local/devices/$base" 2>&1)"
	via_vault="$(bash "$ROOT/scripts/validate-note-id.sh" "vault/devices/$base" 2>&1)"
	rm -f "$TMP"
	case "$via_local" in *"ID MISMATCH"*) ok "guard-local" "a wrong id is caught via local/" ;;
		*) bad "guard-local" "no mismatch reported via local/" ;; esac
	case "$via_vault" in *"ID MISMATCH"*) ok "guard-vault" "a wrong id is caught via vault/ too" ;;
		*) bad "guard-vault" "the guard is SILENT via vault/ — the alias disables it" ;; esac
else
	ok "guard" "no local/devices on this machine — skipped"
fi
[ "$made_alias" -eq 1 ] && rm -f "$ROOT/vault"

if [ "$fail" -ne 0 ]; then echo "FAIL test-vault-alias" >&2; exit 1; fi
echo "PASS test-vault-alias"
