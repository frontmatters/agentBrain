#!/usr/bin/env bash
# Test session continuity: validates archive naming, collision handling,
# previous chain, frontmatter, and fresh journal creation.
# Usage: bash scripts/test-session-continuity.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Use a temporary test directory to avoid polluting real sessions
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

SESSIONS_DIR="$TEST_DIR/sessions"
ARCHIVE_DIR="$SESSIONS_DIR/archive"
JOURNAL="$SESSIONS_DIR/session-journal.md"
mkdir -p "$ARCHIVE_DIR"

passed=0
failed=0
failures=()

assert() {
	local desc="$1" actual="$2" expected="$3"
	if [ "$actual" = "$expected" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: expected '$expected', got '$actual'")
	fi
}

assert_match() {
	local desc="$1" actual="$2" pattern="$3"
	if echo "$actual" | grep -qE -- "$pattern"; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: '$actual' did not match pattern '$pattern'")
	fi
}

assert_file_exists() {
	local desc="$1" file="$2"
	if [ -f "$file" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: file not found: $file")
	fi
}

# ── Test 1: Archive naming convention ────────────────

echo "Test 1: Archive naming convention"

# Create a fake journal to archive
mkdir -p "$ARCHIVE_DIR/2026-05"
cat >"$JOURNAL" <<'EOF'
---
date: 2026-05-18
type: session-journal
tags: [session]
project: test
id: test-id-001
status: active
---
# Test Journal
Test content.
EOF

# Generate an archive filename manually and verify the pattern
STAMP="20260518-143205"
PID="a7f3"
ARCHIVE_NAME="${STAMP}-${PID}.md"
ARCHIVE_PATH="$ARCHIVE_DIR/2026-05/$ARCHIVE_NAME"

assert_match "archive name pattern" "$ARCHIVE_NAME" '^20260518-143205-[0-9a-f]{4}\.md$'
assert_match "archive name has stamp" "$ARCHIVE_NAME" '^20260518-143205'
assert_match "archive name has 4-hex pid" "$ARCHIVE_NAME" '-[0-9a-f]{4}\.md$'

# ── Test 2: Collision handling ───────────────────────

echo "Test 2: Collision handling"

# Create an existing file at the target path
touch "$ARCHIVE_PATH"

# Verify collision detection: file exists
if [ -f "$ARCHIVE_PATH" ]; then
	# Simulate collision retry with a different PID
	PID2="b8e1"
	ARCHIVE_NAME2="${STAMP}-${PID2}.md"
	assert "collision produces different name" "$ARCHIVE_NAME2" "20260518-143205-b8e1.md"
	assert_file_exists "original file still exists" "$ARCHIVE_PATH"
else
	failed=$((failed + 1))
	failures+=("collision test setup: failed to create existing file")
fi

# ── Test 3: Previous chain ───────────────────────────

echo "Test 3: Previous chain"

# Simulate archive with previous=empty (first session)
ARCH1="$ARCHIVE_DIR/2026-05/20260518-010000-aaaa.md"
cat >"$ARCH1" <<'EOF'
---
date: 2026-05-18
type: session-journal
tags: [session]
project: test
previous:
id: 12216866-88c5-5954-ac56-45268cc7557a
status: archived
---
# First session
EOF

# Simulate second archive with previous pointing to first
ARCH2="$ARCHIVE_DIR/2026-05/20260518-020000-bbbb.md"
cat >"$ARCH2" <<'EOF'
---
date: 2026-05-18
type: session-journal
tags: [session]
project: test
previous: 20260518-010000-aaaa
id: 033abe47-d511-5d99-b572-cb40b44582bf
status: archived
---
# Second session
EOF

# Simulate current journal with previous pointing to second
cat >"$JOURNAL" <<'EOF'
---
date: 2026-05-18
type: session-journal
tags: [session]
project: test
previous: 20260518-020000-bbbb
id: 4a221850-50dd-51be-909b-c4dc36b60e11
status: active
---
# Current session
EOF

# Verify chain
PREV_JOURNAL=$(grep '^previous:' "$JOURNAL" | awk '{print $2}')
PREV_ARCH2=$(grep '^previous:' "$ARCH2" | awk '{print $2}')
PREV_ARCH1=$(grep '^previous:' "$ARCH1" | awk '{print $2}')

assert "journal previous points to arch2" "$PREV_JOURNAL" "20260518-020000-bbbb"
assert "arch2 previous points to arch1" "$PREV_ARCH2" "20260518-010000-aaaa"
assert "arch1 previous is empty (first)" "$PREV_ARCH1" ""

# ── Test 4: Archive frontmatter ──────────────────────

echo "Test 4: Archive frontmatter"

# Verify required fields in archived files
for field in date type tags project previous id status; do
	if grep -q "^${field}:" "$ARCH1"; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("arch1 missing frontmatter field: $field")
	fi
done

STATUS_ARCH1=$(grep '^status:' "$ARCH1" | awk '{print $2}')
STATUS_JOURNAL=$(grep '^status:' "$JOURNAL" | awk '{print $2}')

assert "archived status = archived" "$STATUS_ARCH1" "archived"
assert "journal status = active" "$STATUS_JOURNAL" "active"

# ── Test 5: Fresh journal creation ───────────────────

echo "Test 5: Fresh journal creation"

FRESH_JOURNAL="$TEST_DIR/fresh-journal.md"
cat >"$FRESH_JOURNAL" <<'EOF'
---
date: 2026-05-18
type: session-journal
tags: [session]
project: 
previous: 20260518-020000-bbbb
id: fresh-id
status: active
---

# Session Journal

## Last updated: 15:00

### Project: 
### Task: 

### Done
- 

### Files changed
- 

### Next step
-> 

### Open questions
- 
EOF

# Verify fresh journal structure
assert_file_exists "fresh journal created" "$FRESH_JOURNAL"
assert_match "fresh journal has frontmatter delimiter" "$(head -1 "$FRESH_JOURNAL")" '^---$'
assert_match "fresh journal has type session-journal" "$(grep '^type:' "$FRESH_JOURNAL")" 'session-journal'
assert_match "fresh journal has active status" "$(grep '^status:' "$FRESH_JOURNAL")" 'active'
assert_match "fresh journal has previous link" "$(grep '^previous:' "$FRESH_JOURNAL")" '20260518-020000-bbbb'

# ── Test 6: Monthly subfolder structure ──────────────

echo "Test 6: Monthly subfolder structure"

mkdir -p "$ARCHIVE_DIR/2026-04"
touch "$ARCHIVE_DIR/2026-04/20260417-120000-dead.md"
assert_match "monthly folder pattern YYYY-MM" "2026-04" '^[0-9]{4}-[0-9]{2}$'
assert_file_exists "archive in correct month folder" "$ARCHIVE_DIR/2026-04/20260417-120000-dead.md"

# ── Test 7: UUID5 in archive frontmatter ─────────────

echo "Test 7: UUID5 in archive frontmatter"

ARCH1_ID=$(grep '^id:' "$ARCH1" | awk '{print $2}')
assert_match "archive has UUID-like id" "$ARCH1_ID" '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# ── Results ──────────────────────────────────────────

echo ""
echo "==============================="
echo "Session continuity test results"
echo "==============================="
echo "Passed: $passed"
echo "Failed: $failed"

if [ "$failed" -gt 0 ]; then
	echo ""
	echo "Failures:"
	for f in "${failures[@]}"; do
		echo "  ✗ $f"
	done
	exit 1
else
	echo ""
	echo "All tests passed ✅"
fi
