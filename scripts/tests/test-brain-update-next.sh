#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Public RC upgrade, deliberate downgrade and stable-promotion ancestry.
set -uo pipefail
ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
bare="$T/public.git"; src="$T/source"; consumer="$T/consumer"
git init -q --bare "$bare"; git init -q -b main "$src"
git -C "$src" config user.name test; git -C "$src" config user.email t@t
printf '1.13.1\n' > "$src/VERSION"
git -C "$src" add VERSION; git -C "$src" commit -qm stable
git -C "$src" tag v1.13.1; git -C "$src" remote add origin "$bare"
git -C "$src" push -q origin main --tags
git clone -q -b main "$bare" "$consumer"
export AGENTBRAIN_DIR="$T/brain"
mkdir -p "$AGENTBRAIN_DIR/vault/update"
printf '{"channel":"next","mode":"tag","source":"origin","branches":{"next":"next","stable":"main"}}\n' > "$AGENTBRAIN_DIR/vault/update/config.json"
run() { AGENTBRAIN_DEV_DIR="$consumer" bash "$ROOT/scripts/brain-update.sh" --repo "$consumer" "$@"; }
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }
git -C "$src" checkout -qb next
printf '1.14.0-rc.1\n' > "$src/VERSION"
git -C "$src" commit -qam rc1; git -C "$src" tag v1.14.0-rc.1; git -C "$src" push -q origin next --tags
rc=0; out="$(run --check 2>&1)" || rc=$?
[ "$rc" = 10 ] && [[ "$out" == *'update available'* ]] && ok 'stable checkout fetches its first RC in the same run' || bad "first RC fetch ($rc)"
rc=0; run --doctor-cmd true >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(<"$consumer/VERSION")" = 1.14.0-rc.1 ] && ok 'stable → RC fast-forwards without touching public main' || bad "stable → RC ($rc)"
[ "$(git --git-dir="$bare" rev-parse refs/heads/main)" != "$(git -C "$consumer" rev-parse HEAD)" ] || bad 'RC changed stable main'
printf '1.14.0-rc.2\n' > "$src/VERSION"
git -C "$src" commit -qam rc2; git -C "$src" tag v1.14.0-rc.2; git -C "$src" push -q origin next --tags
before="$(git -C "$consumer" rev-parse HEAD)"
rc=0; run --doctor-cmd false >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && [ "$(git -C "$consumer" rev-parse HEAD)" = "$before" ] && ok 'failing RC doctor rolls back exact anchor' || bad 'failing RC doctor did not roll back'
rc=0; run --doctor-cmd true >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(<"$consumer/VERSION")" = 1.14.0-rc.2 ] && ok 'RC1 → RC2 fast-forwards' || bad "RC1 → RC2 ($rc)"
python3 - "$AGENTBRAIN_DIR/vault/update/config.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d['channel'] = 'stable'
with open(p, 'w') as f: json.dump(d, f)
PY
before="$(git -C "$consumer" rev-parse HEAD)"
rc=0; run --doctor-cmd true >/dev/null 2>&1 || rc=$?
[ "$rc" = 11 ] && [ "$(git -C "$consumer" rev-parse HEAD)" = "$before" ] && ok 'return to older stable refuses implicit downgrade' || bad "implicit downgrade ($rc)"
rc=0; run --switch --doctor-cmd true >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(<"$consumer/VERSION")" = 1.13.1 ] && ok 'explicit --switch returns to older stable with doctor' || bad "explicit stable rollback ($rc)"
# Return to the saved local branch (still at RC2) to test the independent
# RC→stable promotion path rather than the detached downgrade checkout.
git -C "$consumer" checkout -q main
# Final stable snapshot descends from the latest public RC, so RC users can FF.
git -C "$src" checkout -q -b stable-from-rc next
printf '1.14.0\n' > "$src/VERSION"
git -C "$src" commit -qam stable-v114; git -C "$src" tag v1.14.0
git -C "$src" push -q origin stable-from-rc:main v1.14.0
rc=0; run --doctor-cmd true >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(<"$consumer/VERSION")" = 1.14.0 ] && ok 'stable user FFs after stable promotion' || bad "stable promotion FF ($rc)"
printf 'brain-update-next: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
