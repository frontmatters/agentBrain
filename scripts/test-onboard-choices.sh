#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-onboard-choices.sh — validate system/skills/onboard/choices.json and keep
# its supported-locale set in sync with the single source (scripts/lib/_strings.sh).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHOICES="$ROOT_DIR/system/skills/onboard/choices.json"
STRINGS="$ROOT_DIR/scripts/lib/_strings.sh"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# 1) choices.json is valid JSON with the expected shape
if python3 - "$CHOICES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get("fields"), dict) and d["fields"], "fields missing/empty"
for name, f in d["fields"].items():
    assert f.get("type") in ("choice", "text"), f"{name}: bad type"
    if f["type"] == "choice":
        opts = f.get("options")
        assert isinstance(opts, list) and len(opts) >= 2, f"{name}: choice needs >=2 options"
assert isinstance(d.get("locales", {}).get("supported"), list) and d["locales"]["supported"], "locales.supported missing"
PY
then pass "choices.json valid + well-shaped"; else fail "choices.json invalid"; fi

# 2) supported locales EXACTLY match the _strings.sh normalize case (single source)
STRINGS_CODES="$(sed -n '/# Normalize/,/esac/p' "$STRINGS" | grep -oE '^[[:space:]]*[a-z|]+\)' | head -1 | tr -d $' \t)' | tr '|' '\n' | sort | paste -sd, -)"
JSON_CODES="$(python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1]))["locales"]["supported"])))' "$CHOICES")"
if [ "$STRINGS_CODES" = "$JSON_CODES" ]; then
  pass "supported locales match _strings.sh ($JSON_CODES)"
else
  fail "locale mismatch: choices.json=[$JSON_CODES] vs _strings.sh=[$STRINGS_CODES]"
fi

# 3) the enum fields G5 targets are present and are choices
for field in verbosity autonomy design channel updateMode scope language artifactLanguage; do
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); f=d["fields"].get(sys.argv[2]); sys.exit(0 if f and f["type"]=="choice" else 1)' "$CHOICES" "$field"; then
    pass "$field is a fixed choice"; else fail "$field missing or not a choice"; fi
done

# 4) doctor runs the schema validation
if grep -q 'test-onboard-choices.sh' "$ROOT_DIR/scripts/doctor.sh"; then
  pass "doctor runs onboard-choices test"; else fail "doctor does not run onboard-choices test"; fi

# 5) SKILL.md references the schema and folds locale into the language step
SKILL="$ROOT_DIR/system/skills/onboard/SKILL.md"
if grep -q 'choices.json' "$SKILL"; then pass "SKILL.md cites choices.json"; else fail "SKILL.md does not cite choices.json"; fi
if grep -q 'derived from the Step 1 language' "$SKILL"; then pass "SKILL.md derives locale (G6)"; else fail "SKILL.md still asks locale separately"; fi

# 6) v2 shape: every choice option is an object with value+desc; language has no Mixed and >=5 languages; artifactLanguage is conditional
if python3 - "$CHOICES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
f = d["fields"]
for name, fld in f.items():
    if fld.get("type") != "choice":
        continue
    for o in fld["options"]:
        assert isinstance(o, dict) and o.get("value") and o.get("desc"), f"{name}: option must be object with value+desc"
langs = [o["value"] for o in f["language"]["options"]]
assert "Mixed" not in langs, "Mixed must be gone (replaced by artifactLanguage)"
assert len(langs) >= 5, "popular languages expected"
assert f["artifactLanguage"].get("condition", {}).get("not") == "English", "artifactLanguage must be conditional on language != English"
PY
then pass "v2 shape: desc per option, no Mixed, conditional artifactLanguage"; else fail "v2 shape invalid"; fi

# 7) proto drift guard (local machines only): flow-spec Q1 values must match choices.json language values
FLOWSPEC="$ROOT_DIR/local/tools/onboard-proto/flow-spec.json"
if [ -f "$FLOWSPEC" ]; then
  if python3 - "$CHOICES" "$FLOWSPEC" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
s = json.load(open(sys.argv[2]))
cv = [o["value"] for o in c["fields"]["language"]["options"]]
q1 = next(n for n in s["nodes"] if n["id"] == "Q1")
sv = [o["value"] for o in q1["options"]]
assert cv == sv, f"language drift: choices={cv} spec={sv}"
PY
  then pass "no drift: flow-spec Q1 == choices.json language"; else fail "flow-spec drifted from choices.json"; fi
fi

# 8) SKILL.md landed the language redesign
if grep -q 'artifactLanguage' "$SKILL"; then pass "SKILL.md has artifactLanguage"; else fail "SKILL.md misses artifactLanguage"; fi
if ! grep -q 'Mixed' "$SKILL"; then pass "SKILL.md no longer mentions Mixed"; else fail "SKILL.md still mentions Mixed"; fi
if grep -q 'secrets-helper' "$SKILL"; then pass "SKILL.md recommends secrets-helper on macOS"; else fail "SKILL.md misses the macOS secrets-helper recommendation"; fi

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
