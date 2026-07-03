#!/usr/bin/env bash
# test-validate-note-id.sh — unit tests for scripts/validate-note-id.sh.
# Safety-critical: this validator backs the entire 3-layer agent-discipline
# enforcement framework. If it has a silent bug (false negative on bad id,
# false positive on good id) the whole framework fails silently.
#
# Runs in doctor's local_checks. Creates a tmp fixture vault, runs the
# validator against assorted inputs, asserts exit codes.
#
# Usage: bash scripts/test-validate-note-id.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-note-id.sh"

# --- Build fixture vault ---
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-validate-note-id-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/scripts" "$FIXTURE/local/learnings" "$FIXTURE/local/sessions/archive"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" "$FIXTURE/scripts/"

NS="$(python3 -c 'import json; print(json.load(open("'"$FIXTURE"'/brain.json"))["namespace"])')"

# Helper: compute expected uuid5 for a vault-relative path (no ext)
expected_uuid() {
	python3 -c "import uuid; print(uuid.uuid5(uuid.UUID('$NS'), 'agentBrain/$1'))"
}

PASS=0
FAIL=0
fail() { echo "  ✗ FAIL: $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }

run_case() {
	local desc="$1" file="$2" expected_exit="$3"
	local actual_exit=0
	bash "$VALIDATOR" "$file" >/dev/null 2>&1 || actual_exit=$?
	if [ "$actual_exit" = "$expected_exit" ]; then
		pass "$desc (exit=$actual_exit)"
	else
		fail "$desc (got exit=$actual_exit, want $expected_exit)"
	fi
}

# Case 1: valid id passes (exit 0)
CORRECT_UUID="$(expected_uuid "local/learnings/good")"
cat > "$FIXTURE/local/learnings/good.md" <<EOF
---
date: 2026-05-24
type: learning
tags: [test]
id: $CORRECT_UUID
---
# Good
EOF
run_case "valid id passes" "$FIXTURE/local/learnings/good.md" 0

# Case 2: wrong id fails (exit 1)
cat > "$FIXTURE/local/learnings/bad.md" <<EOF
---
date: 2026-05-24
type: learning
tags: [test]
id: 00000000-0000-0000-0000-000000000000
---
# Bad
EOF
run_case "wrong id fails" "$FIXTURE/local/learnings/bad.md" 1

# Case 3: no frontmatter → no-op (exit 0, nothing to validate)
echo "Just text, no frontmatter." > "$FIXTURE/local/learnings/no-fm.md"
run_case "no frontmatter is no-op" "$FIXTURE/local/learnings/no-fm.md" 0

# Case 4: no id field → no-op
cat > "$FIXTURE/local/learnings/no-id.md" <<EOF
---
date: 2026-05-24
type: learning
tags: [test]
---
# No id field
EOF
run_case "no id field is no-op" "$FIXTURE/local/learnings/no-id.md" 0

# Case 5: exempt path (sessions/archive) → no-op even with wrong id
cat > "$FIXTURE/local/sessions/archive/2026-05-24-fake.md" <<EOF
---
date: 2026-05-24
type: session
id: 00000000-0000-0000-0000-000000000000
---
EOF
run_case "exempt path with wrong id is no-op" "$FIXTURE/local/sessions/archive/2026-05-24-fake.md" 0

# Case 6: non-md file → no-op
echo "binary-ish content" > "$FIXTURE/local/learnings/not-markdown.txt"
run_case "non-md file is no-op" "$FIXTURE/local/learnings/not-markdown.txt" 0

# Case 7: file outside brain (no brain.json above) → no-op
OUTSIDE="$(mktemp -d "${TMPDIR:-/tmp}/outside-brain-XXXXXX")"
printf '%s\n' "---" "id: anything" "---" > "$OUTSIDE/orphan.md"
run_case "file outside brain is no-op" "$OUTSIDE/orphan.md" 0
rm -rf "$OUTSIDE"

# Case 8: missing file → no-op
run_case "missing file is no-op" "$FIXTURE/local/learnings/nonexistent.md" 0

# Case 9: extracted learnings use a content-hash id strategy (not path-uuid5) →
# exempt, like check-local-content.sh. Must be no-op even with a non-uuid5 id.
mkdir -p "$FIXTURE/local/learnings/extracted"
cat > "$FIXTURE/local/learnings/extracted/abc12345-learning-from-x.md" <<EOF
---
id: abc12345
contentHash: deadbeefcafef00d
---
# Extracted
EOF
run_case "extracted learning (content-hash id) is exempt" "$FIXTURE/local/learnings/extracted/abc12345-learning-from-x.md" 0

# Case 10: youtube-digest transcripts/MOCs are machine-generated → exempt.
mkdir -p "$FIXTURE/local/youtube-digest/development"
cat > "$FIXTURE/local/youtube-digest/development/vid.md" <<EOF
---
id: 00000000-0000-0000-0000-000000000000
---
# Transcript
EOF
run_case "youtube-digest note is exempt" "$FIXTURE/local/youtube-digest/development/vid.md" 0

# --- Report ---
echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "test-validate-note-id: $FAIL FAILED, $PASS passed"
	exit 1
fi
echo "test-validate-note-id: ✅ $PASS tests passed"
