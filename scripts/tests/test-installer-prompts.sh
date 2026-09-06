#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Static/contract checks for the dependency-free installer prompt helper.
# Also keeps scripts/installer/prompt-api.json in sync with the implementation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/scripts/installer/prompt-helper.sh"

test -f "$HELPER"
bash -n "$HELPER"
grep -q 'stty -icanon -echo -icrnl min 1 time 0' "$HELPER"
grep -q "REPLY=ESC" "$HELPER"
grep -q 'REPLY=UP' "$HELPER"
grep -q 'REPLY=DOWN' "$HELPER"
grep -q 'REPLY=ENTER' "$HELPER"
grep -q 'ab_prompt_cleanup' "$HELPER"
grep -q 'ab_prompt_multi' "$HELPER"
grep -q 'ab_prompt_confirm' "$HELPER"
grep -q "read -r -s -d ''" "$HELPER"   # NUL delimiter: LF Enter must not read as EOF

# The prompt-api.json spec must stay in sync with the implementation.
API="$ROOT/scripts/installer/prompt-api.json"
test -f "$API"
python3 - "$API" "$HELPER" <<'PY'
import json, sys
spec, src = open(sys.argv[1]).read(), open(sys.argv[2]).read()
api = json.loads(spec)
missing = [f for f in api["functions"] if f != "text" and f"ab_prompt_{f}(" not in src]
assert not missing, f"functions missing in helper: {missing}"
for t, d in api["types"].items():
    if t == "text":
        assert d.get("status") == "planned"
        continue
    for flag in d["flags"]:
        flagname = flag.split()[0]
        assert flagname in src, f"flag {flagname} not implemented for {t}"
for style, needle in {"numbered": '"$style" != 1', "checkbox": '"$style" = 1', "plain": '"$style" = 2'}.items():
    assert needle in src, f"style {style} not implemented"
print("spec-sync ok")
PY
# fase 3: symmetrische bootstrap-familie + platform_os dispatch + flow-journal
test -f "$ROOT/scripts/installer/flow.sh" || { echo "FAIL flow.sh ontbreekt"; exit 1; }
grep -q "flow_init" "$ROOT/scripts/installer/install.sh" || { echo "FAIL install.sh mist flow_init"; exit 1; }
grep -q "bootstrap/macos.sh" "$ROOT/scripts/installer/install.sh" || { echo "FAIL installer mist bootstrap-macos dispatch"; exit 1; }
grep -q "bootstrap/linux.sh" "$ROOT/scripts/installer/install.sh" || { echo "FAIL installer mist bootstrap-linux dispatch"; exit 1; }
for step in install-prerequisites.sh setup.sh; do
	grep -q "$step" "$ROOT/scripts/installer/bootstrap/linux.sh" || { echo "FAIL bootstrap-linux mist $step (2-stappen-contract)"; exit 1; }
done
for step in configure-pi.sh doctor.sh; do
	grep -q "$step" "$ROOT/scripts/setup/setup.sh" || { echo "FAIL setup.sh mist $step (single owner pi+doctor)"; exit 1; }
done
for f in installer/bootstrap/macos.sh installer/bootstrap/linux.sh; do
	n=$(grep -c "flow_begin" "$ROOT/scripts/$f")
	[ "$n" -ge 2 ] || { echo "FAIL $f: $n flow_begin (verwacht >=2)"; exit 1; }
done
echo "fase 3 + flow-journal: ok"

echo 'test-installer-prompts: PASS'
