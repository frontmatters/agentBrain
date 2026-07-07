#!/usr/bin/env bash
# test-new-note.sh — unit tests for scripts/new-note.sh.
# Layer 2 of the agent-discipline framework: ensures the scaffold produces
# notes that pass validate-note-id.sh (= correct frontmatter + UUID5 parity).
#
# Runs in doctor's local_checks.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-new-note-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/scripts"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" \
   "$ROOT_DIR/scripts/validate-note-id.sh" \
   "$ROOT_DIR/scripts/new-note.sh" \
   "$FIXTURE/scripts/"

PASS=0
FAIL=0
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }

# Case 1: creates note + frontmatter present
OUT="$(cd "$FIXTURE" && bash scripts/new-note.sh learning local/learnings/case-one "Case One")"
if [ -f "$OUT" ]; then pass "creates note at expected path"; else fail "no note created at $OUT"; fi

if head -1 "$OUT" | grep -q "^---"; then pass "frontmatter starts"; else fail "no frontmatter"; fi
if grep -q "^id: " "$OUT"; then pass "id field present"; else fail "no id field"; fi
if grep -q "^type: learning" "$OUT"; then pass "type matches argument"; else fail "type wrong"; fi
if grep -q "^# Case One" "$OUT"; then pass "title rendered"; else fail "title missing"; fi

# Case 2: generated id passes validate-note-id.sh (the whole point)
if (cd "$FIXTURE" && bash scripts/validate-note-id.sh "$OUT"); then
	pass "generated note passes validator"
else
	fail "generated note FAILS validator (uuid5 mismatch — Layer 2 broken)"
fi

# Case 3: refuses to overwrite existing file
if (cd "$FIXTURE" && bash scripts/new-note.sh learning local/learnings/case-one "Try again") 2>/dev/null; then
	fail "overwrote existing file (should have refused)"
else
	pass "refuses to overwrite existing"
fi

# Case 4: each supported type produces a valid note
for t in project backlog feedback reference session spec; do
	tout="$(cd "$FIXTURE" && bash scripts/new-note.sh "$t" "local/learnings/case-$t" "Case $t")"
	if (cd "$FIXTURE" && bash scripts/validate-note-id.sh "$tout"); then
		pass "type=$t produces valid note"
	else
		fail "type=$t produces invalid note"
	fi
done

# Case 4b: spec type includes a `version:` frontmatter field (default 1.0.0)
if grep -q '^version: 1\.0\.0$' "$FIXTURE/local/learnings/case-spec.md" 2>/dev/null; then
	pass "type=spec scaffolds version: 1.0.0"
else
	fail "type=spec missing version: 1.0.0 in frontmatter"
fi

# Case 4c: project type scaffolds a default `status: active` (check-project-status-enum
# rejects a project note with no status, so the scaffold must supply one). Note the
# /index guard redirects a project dir path to <dir>/index.md.
if grep -q '^status: active$' "$FIXTURE/local/learnings/case-project/index.md" 2>/dev/null; then
	pass "type=project scaffolds status: active"
else
	fail "type=project missing status: active in frontmatter"
fi

# Case 5: unknown type fails with exit 2 (usage error)
if (cd "$FIXTURE" && bash scripts/new-note.sh garbagetype local/learnings/badtype "test") 2>/dev/null; then
	fail "unknown type accepted (should reject)"
else
	pass "unknown type rejected"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "test-new-note: $FAIL failed, $PASS passed"
	exit 1
fi
echo "test-new-note: ✅ $PASS tests passed"
