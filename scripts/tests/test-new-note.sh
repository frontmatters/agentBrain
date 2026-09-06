#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-new-note.sh — unit tests for scripts/new-note.sh.
# Layer 2 of the agent-discipline framework: ensures the scaffold produces
# notes that pass validate-note-id.sh (= correct frontmatter + UUID5 parity).
#
# Runs in doctor's local_checks.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-new-note-XXXXXX")"
# A fixture brain has the layout setup makes: vault/ is the directory, local/ the alias.
mkdir -p "$FIXTURE/vault" && ln -sfn vault "$FIXTURE/local"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/scripts" "$FIXTURE/system/lib" "$FIXTURE/external/alpha-app"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/system/lib/context.sh" "$FIXTURE/system/lib/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" \
   "$ROOT_DIR/scripts/hooks/validate-note-id.sh" \
   "$ROOT_DIR/scripts/new-note.sh" \
   "$FIXTURE/scripts/"
mkdir -p "$FIXTURE/local"
cat > "$FIXTURE/vault/.space-map.json" <<EOF
{
  "by-alias": { "alpha": "alpha", "beta": "beta" },
  "by-code-root": { "$FIXTURE/external/alpha-app": "alpha" }
}
EOF

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
if (cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$OUT"); then
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
	if (cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$tout"); then
		pass "type=$t produces valid note"
	else
		fail "type=$t produces invalid note"
	fi
done

# Case 4b: spec type includes a `version:` frontmatter field (default 1.0.0)
if grep -q '^version: 1\.0\.0$' "$FIXTURE/vault/learnings/case-spec.md" 2>/dev/null; then
	pass "type=spec scaffolds version: 1.0.0"
else
	fail "type=spec missing version: 1.0.0 in frontmatter"
fi

# Case 4c: project type scaffolds a default `status: active` (check-project-status-enum
# rejects a project note with no status, so the scaffold must supply one). Note the
# /index guard redirects a project dir path to <dir>/index.md.
if grep -q '^status: active$' "$FIXTURE/vault/learnings/case-project/index.md" 2>/dev/null; then
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

# Case: task type produces status: pending + valid note
OUT_T="$(cd "$FIXTURE" && bash scripts/new-note.sh task local/queue/frontmatters/probe "Probe")"
if grep -q "^type: task" "$OUT_T"; then pass "task type matches"; else fail "task type wrong"; fi
if grep -q "^status: pending" "$OUT_T"; then pass "task status pending"; else fail "task status missing"; fi
if (cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$OUT_T"); then pass "task note passes validator"; else fail "task note fails validator"; fi

# --from uses the actual work repo instead of the harness CWD.
OUT_FROM="$(cd "$FIXTURE" && bash scripts/new-note.sh project local/projects/from-case "From Case" --from "$FIXTURE/external/alpha-app")"
if [ "$(realpath "$OUT_FROM")" = "$(realpath "$FIXTURE/vault/spaces/alpha/projects/from-case/index.md")" ] && [ -f "$OUT_FROM" ]; then
	pass "--from routes through the supplied repo code-root"
else
	fail "--from routed to unexpected path: $OUT_FROM"
fi
if grep -q '^space: alpha$' "$OUT_FROM"; then pass "--from writes space frontmatter"; else fail "--from missing space frontmatter"; fi

# A fully-qualified target path dominates an unrelated harness CWD code-root.
OUT_PATH_WINS="$(cd "$FIXTURE/external/alpha-app" && bash "$FIXTURE/scripts/new-note.sh" project local/spaces/beta/projects/path-wins "Path Wins")"
if [ -f "$OUT_PATH_WINS" ] && grep -q '^space: beta$' "$OUT_PATH_WINS"; then
	pass "full space path dominates harness CWD"
else
	fail "harness CWD overrode full space path"
fi

# Explicit owner and --from owner must agree.
if (cd "$FIXTURE" && bash scripts/new-note.sh project local/projects/from-conflict "Conflict" --context beta --from "$FIXTURE/external/alpha-app") >/dev/null 2>&1; then
	fail "conflicting --context and --from were accepted"
else
	pass "conflicting --context and --from are rejected"
fi
[ ! -e "$FIXTURE/vault/spaces/beta/projects/from-conflict" ] || fail "conflicting --from wrote a project"

# A typo in --from is a usage error, never a silent shared-vault write.
if (cd "$FIXTURE" && bash scripts/new-note.sh learning local/learnings/from-missing "Missing" --from "$FIXTURE/no-such-repo") >/dev/null 2>&1; then
	fail "missing --from path was accepted"
else
	pass "missing --from path is rejected"
fi
[ ! -e "$FIXTURE/vault/learnings/from-missing.md" ] || fail "missing --from wrote a shared note"

# Supplemental project content requires the project's canonical index.md.
if (cd "$FIXTURE" && bash scripts/new-note.sh reference local/projects/incomplete/context "Context") >/dev/null 2>&1; then
	fail "supplemental note created a project without index.md"
else
	pass "project content without index.md is rejected"
fi
[ ! -e "$FIXTURE/vault/projects/incomplete" ] || fail "incomplete project directory was created"

OUT_PROJECT="$(cd "$FIXTURE" && bash scripts/new-note.sh project local/projects/complete "Complete")"
OUT_CONTEXT="$(cd "$FIXTURE" && bash scripts/new-note.sh reference local/projects/complete/context "Context")"
if [ -f "$OUT_PROJECT" ] && [ -f "$OUT_CONTEXT" ]; then
	pass "supplemental content is allowed after project index.md exists"
else
	fail "valid indexed project rejected supplemental content"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "test-new-note: $FAIL failed, $PASS passed"
	exit 1
fi
echo "test-new-note: ✅ $PASS tests passed"
