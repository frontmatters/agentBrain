#!/usr/bin/env bash
# test.sh — regression suite for wash-vault.
#
# Picked up automatically by scripts/checks/check-skill-tests.sh (opt-in
# convention: a skill MAY ship test.sh at its root), so doctor runs it.
#
# wash-vault is the only tool that MUTATES the knowledge base, and every case
# below is a failure it actually produced or hid at some point. It runs against
# a throwaway fixture brain via BRAIN_DIR, never against the real vault.

set -uo pipefail

SKILL_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WASH="$SKILL_DIR/bin/wash-vault"
REAL_ROOT="$(cd -P "$SKILL_DIR/../../.." && pwd -P)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/wash-vault-test.XXXXXX")"
# A fixture brain has the layout setup makes: vault/ is the directory, local/ the alias.
mkdir -p "$FIXTURE/vault" && ln -sfn vault "$FIXTURE/local"
trap 'rm -rf "$FIXTURE"' EXIT

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ok: %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL: %s\n' "$1" >&2; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

# --- fixture brain -----------------------------------------------------------
# resolve_brain_dir() accepts BRAIN_DIR when it points at a real directory; the
# tool then needs system/rules.md, scripts/uuid5-gen.sh and the shared
# exempt-path list. Reuse the real script and list so the test exercises the
# same id strategy and the same exemptions as production.
mkdir -p "$FIXTURE/system" "$FIXTURE/scripts/lib" "$FIXTURE/vault/learnings" \
         "$FIXTURE/vault/addons/demo/runs"
: > "$FIXTURE/system/rules.md"
cp "$REAL_ROOT/scripts/uuid5-gen.sh" "$FIXTURE/scripts/uuid5-gen.sh"
chmod +x "$FIXTURE/scripts/uuid5-gen.sh"
cp "$REAL_ROOT/scripts/lib/exempt-schema-paths.txt" "$FIXTURE/scripts/lib/"
# brain.json carries the UUID5 namespace. Use the real one when it is there, so
# the ids this test computes match production exactly.
#
# It is machine data, generated at install and never tracked, so a release
# payload has none and the unconditional copy failed there: six assertions down,
# in a test that ran nowhere until the skill-test discovery check existed. The
# invariant being measured is that wash-vault and uuid5-gen.sh agree on an id,
# not which namespace they agree under, so a fixed fixture namespace tests the
# same thing wherever the payload came from.
if [ -f "$REAL_ROOT/brain.json" ]; then
	cp "$REAL_ROOT/brain.json" "$FIXTURE/brain.json"
else
	printf '{\n  "namespace": "00000000-0000-4000-8000-000000000000",\n  "version": "1.0"\n}\n' \
		> "$FIXTURE/brain.json"
fi

export BRAIN_DIR="$FIXTURE"

note() { # note <relpath-under-local> <id-line>
    local rel="$1" idline="$2"
    mkdir -p "$FIXTURE/vault/$(dirname "$rel")"
    {
        echo "---"
        echo "date: 2026-01-01"
        echo "type: learning"
        echo "tags: [learning]"
        [ -n "$idline" ] && echo "$idline"
        echo "status: active"
        echo "---"
        echo
        echo "# fixture"
    } > "$FIXTURE/vault/$rel"
}

want_id() { bash "$FIXTURE/scripts/uuid5-gen.sh" "local/${1%.md}"; }

echo "wash-vault test.sh"

# --- 1. a correct id is left alone ------------------------------------------
note "learnings/correct.md" "id: $(want_id learnings/correct.md)"
"$WASH" --fix --scope learnings/correct.md >/dev/null 2>&1
check "correct id is a no-op" \
    "$(grep -c '^id:' "$FIXTURE/vault/learnings/correct.md")" "1"
check "correct id keeps its value" \
    "$(grep '^id:' "$FIXTURE/vault/learnings/correct.md")" \
    "id: $(want_id learnings/correct.md)"

# --- 2. a wrong id is corrected ----------------------------------------------
note "learnings/wrong.md" "id: 00000000-0000-0000-0000-000000000000"
"$WASH" --fix --scope learnings/wrong.md >/dev/null 2>&1
check "wrong id is replaced" \
    "$(grep '^id:' "$FIXTURE/vault/learnings/wrong.md")" \
    "id: $(want_id learnings/wrong.md)"

# --- 3. an EMPTY id is filled in place, never appended -----------------------
# Regression: the empty value did not match the id regex, so the tool took the
# "missing id" path and appended a second `id:` key, leaving invalid YAML that
# the detector then accepted.
note "learnings/empty.md" "id:"
"$WASH" --fix --scope learnings/empty.md >/dev/null 2>&1
check "empty id yields exactly one id key" \
    "$(grep -c '^id:' "$FIXTURE/vault/learnings/empty.md")" "1"
check "empty id is filled with the canonical value" \
    "$(grep '^id:' "$FIXTURE/vault/learnings/empty.md")" \
    "id: $(want_id learnings/empty.md)"

# --- 4. a missing id is inserted --------------------------------------------
note "learnings/missing.md" ""
"$WASH" --fix --scope learnings/missing.md >/dev/null 2>&1
check "missing id is inserted" \
    "$(grep -c '^id:' "$FIXTURE/vault/learnings/missing.md")" "1"

# --- 5. exempt paths are never touched ---------------------------------------
# Regression: the fixer kept its own hand-copied exempt list, which had drifted
# from the detector's. It would have rewritten benchmark fixtures that carry
# deliberate placeholder ids.
note "addons/demo/runs/fixture.md" "id: deliberate-placeholder-id"
"$WASH" --fix >/dev/null 2>&1
check "exempt path keeps its placeholder id" \
    "$(grep '^id:' "$FIXTURE/vault/addons/demo/runs/fixture.md")" \
    "id: deliberate-placeholder-id"

# --- 6. --scope accepts a single file, from any working directory ------------
# Regression: scopes were resolved against the caller's cwd rather than local/,
# and os.walk() yields nothing for a file, so a file scope examined zero files
# and still reported success.
note "learnings/scoped.md" "id: 00000000-0000-0000-0000-000000000000"
out="$(cd / && "$WASH" --scope learnings/scoped.md 2>&1)"
case "$out" in
    *"examined 1 file"*) ok "file scope examines exactly one file from any cwd" ;;
    *) bad "file scope from unrelated cwd (got: $out)" ;;
esac
out="$(cd / && "$WASH" --scope local/learnings/scoped.md 2>&1)"
case "$out" in
    *"examined 1 file"*) ok "a local/-prefixed scope resolves too" ;;
    *) bad "local/-prefixed scope (got: $out)" ;;
esac

# --- 7. a scope matching nothing is an error, not a clean bill ---------------
# Regression: zero files examined printed the same success line as a clean
# vault. Never report a verdict without the denominator it covers.
out="$("$WASH" --scope does/not/exist 2>&1)"; rc=$?
check "empty scope exits non-zero" "$([ $rc -ne 0 ] && echo yes || echo no)" "yes"
case "$out" in
    *"0 files in scope"*) ok "empty scope says nothing was examined" ;;
    *) bad "empty scope message (got: $out)" ;;
esac

# --- 8. the shared exempt list is required, not optional ---------------------
mv "$FIXTURE/scripts/lib/exempt-schema-paths.txt" "$FIXTURE/exempt.bak"
"$WASH" >/dev/null 2>&1; rc=$?
check "a missing exempt list fails loudly" "$([ $rc -ne 0 ] && echo yes || echo no)" "yes"
mv "$FIXTURE/exempt.bak" "$FIXTURE/scripts/lib/exempt-schema-paths.txt"

echo "wash-vault: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
