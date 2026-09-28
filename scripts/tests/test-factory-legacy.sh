#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-factory-legacy.sh: a succeeded factory is archived in its successor's
# legacy directory, and the successor keeps its own history.
#
# Reproduces a successor whose lanes are worktrees of its predecessor's
# repository: archiving the predecessor would strand the successor's history.
# The doctor must say so before anyone moves anything.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DOCTOR="$ROOT/system/skills/factory-builder/bin/factory-doctor.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: expected '$3' in: $(printf '%s' "$2" | tail -5)" ;; esac; }
lacks(){ case "$2" in *"$3"*) bad "$1: did not expect '$3'" ;; *) ok "$1" ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
commit() { git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"; }
factory() { # factory <dir> <lanes-json> [extra-json]
	mkdir -p "$1/releases"; for d in dashboards decisions logs experiments captures renders; do mkdir -p "$1/R&D/$d"; done
	printf '# f\n' > "$1/README.md"
	printf '{"project":"f","lanes":%s%s}\n' "$2" "${3:-}" > "$1/factory.json"
}
run() { bash "$DOCTOR" --factory "$1" 2>&1; }

# 1. a factory without a predecessor: nothing to say
S="$T/root/succ"; mkdir -p "$S"
for l in dev next live; do git init -q "$S/$l"; commit "$S/$l" init; done
factory "$S" '{"dev":"dev","next":"next","live":"live"}'
lacks "no legacy_factory: no legacy notes" "$(run "$S")" "legacy"

# 2. legacy_factory that does not exist
factory "$S" '{"dev":"dev","next":"next","live":"live"}' ',"legacy_factory":"R&D/legacy/gone"'
has "missing legacy: FAIL" "$(run "$S")" "FAIL legacy_factory does not exist"

# 3. the predecessor still beside the others in the registry root
P="$T/root/pred"; mkdir -p "$P"; printf '{"project":"pred"}\n' > "$P/factory.json"
factory "$S" '{"dev":"dev","next":"next","live":"live"}' ",\"legacy_factory\":\"$P\""
out="$(run "$S")"
has "legacy outside R&D/legacy: noted" "$out" "lives outside R&D/legacy/"
has "legacy still beside the others: the registry would list it" "$out" "registry lists it as active"

# 4. archived properly, successor with its own repositories: clean
mkdir -p "$S/R&D/legacy"; mv "$P" "$S/R&D/legacy/pred"
factory "$S" '{"dev":"dev","next":"next","live":"live"}' ',"legacy_factory":"R&D/legacy/pred"'
out="$(run "$S")"
lacks "archived in R&D/legacy: no location note" "$out" "lives outside"
lacks "archived: not listed as active" "$out" "registry lists it"
lacks "own repositories: no history FAIL" "$out" "keeps its git history"

# 5. the trap: the successor's lanes are worktrees of the predecessor's repo
L="$S/R&D/legacy/pred/pred-dev"; git init -q "$L"; commit "$L" init
rm -rf "$S/next"; git -C "$L" worktree add -q -b succ-next "$S/next" >/dev/null 2>&1
out="$(run "$S")"
has "lane that is a worktree of the legacy repo: FAIL" "$out" "FAIL next lane keeps its git history inside the legacy factory"
lacks "the lanes with their own repo are not blamed" "$out" "FAIL dev lane keeps"

# 6. the same trap in a composite factory (lanes under framework.*)
C="$T/root/comp"; mkdir -p "$C/R&D/legacy/old/old-dev" "$C/releases"; printf '# c\n' > "$C/README.md"
git init -q "$C/R&D/legacy/old/old-dev"; commit "$C/R&D/legacy/old/old-dev" init
git -C "$C/R&D/legacy/old/old-dev" worktree add -q -b fw-dev "$C/fw-dev" >/dev/null 2>&1
printf '{"profile":"composite","framework":{"dev":"fw-dev"},"releases":{"root":"releases"},"legacy_factory":"R&D/legacy/old","obeya":{"project":"c"}}\n' > "$C/factory.json"
has "composite: the trap is found through the profile normalizer" "$(run "$C")" "FAIL dev lane keeps its git history inside the legacy factory"

# 7. the layout comes from layout.json, not the script
lit="$(grep -n 'R&D/legacy' "$DOCTOR" | grep -v '^[0-9]*:#' || true)"
[ -z "$lit" ] && ok "the legacy directory is not written into the doctor" || bad "literal in the doctor: $lit"

printf 'factory-legacy: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
