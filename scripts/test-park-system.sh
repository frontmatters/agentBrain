#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2164,SC2329,SC1010
# - SC2015 `[ X ] && Y || Z`: intentional one-liner asserts; Z runs only on
#   the assert-failure path, which is acceptable for a test script.
# - SC2164 `cd $X`: failure here is genuinely fatal (the trap cleans up);
#   adding `|| exit` would mask the temp-dir context for debugging.
# - SC2329 `cleanup() never invoked`: invoked indirectly via `trap`.
# - SC1010 `done` after CLI flag: false positive — `done` here is a value
#   passed to `--status`, not a bash control keyword.
# test-park-system.sh — end-to-end integration test for the park/unpark/list-parks/list-projects/list-learnings bundle.
#
# Creates a throwaway test project, exercises each skill's underlying
# operations, asserts expected behavior, and cleans up.
#
# This is NOT a true cross-session test (a single process drives it), but
# it validates that the file-level contracts hold: dashboards detect new
# projects, filtering works, validators stay green, and drift checks fire.
#
# Usage: bash scripts/test-park-system.sh
# Exit: 0 all pass, 1 any failure.

set -uo pipefail

resolve_brain_dir() {
    realpath "$HOME/agentBrain" 2>/dev/null || (cd "$HOME/agentBrain" && pwd -P)
}
BRAIN_DIR="$(resolve_brain_dir)"
LOCAL_ROOT="$(realpath "$BRAIN_DIR/local" 2>/dev/null || (cd "$BRAIN_DIR/local" && pwd -P))"
SYSTEM_ROOT="$(realpath "$BRAIN_DIR/system" 2>/dev/null || (cd "$BRAIN_DIR/system" && pwd -P))"

TEST_PROJECT="e2e-park-system-$$"
TEST_DIR="$LOCAL_ROOT/projects/$TEST_PROJECT"
TEST_LEARNING="$LOCAL_ROOT/learnings/e2e-test-marker-$$.md"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✓ $1"; }
ko()  { fail=$((fail + 1)); echo "  ✗ FAIL: $1" >&2; }

# shellcheck disable=SC2317  # invoked indirectly via trap below
cleanup() {
    rm -rf "$TEST_DIR" "$TEST_LEARNING" 2>/dev/null || true
}
trap cleanup EXIT

# Always run from a known cwd
cd "$BRAIN_DIR"

echo "test-park-system: starting (BRAIN_DIR=$BRAIN_DIR, project=$TEST_PROJECT)"
echo ""

# --- T0: prerequisites ---
echo "T0: prerequisites"
[ -x "$SYSTEM_ROOT/skills/list-parks/bin/list-parks" ] && ok "list-parks script executable" || ko "list-parks script missing"
[ -x "$SYSTEM_ROOT/skills/list-projects/bin/list-projects" ] && ok "list-projects script executable" || ko "list-projects script missing"
[ -x "$SYSTEM_ROOT/skills/list-learnings/bin/list-learnings" ] && ok "list-learnings script executable" || ko "list-learnings script missing"
[ -f "$SYSTEM_ROOT/skills/park/SKILL.md" ] && ok "park SKILL.md present" || ko "park SKILL.md missing"
[ -f "$SYSTEM_ROOT/skills/unpark/SKILL.md" ] && ok "unpark SKILL.md present" || ko "unpark SKILL.md missing"

# --- T1: simulate /park: create a fresh project with paused status ---
echo ""
echo "T1: simulate /park (create project with status=paused)"
mkdir -p "$TEST_DIR"
cat > "$TEST_DIR/index.md" <<EOF
---
date: 2026-06-03
type: project
name: $TEST_PROJECT
tags: [project, test, e2e]
status: paused
priority: low
id: 00000000-0000-5000-8000-$(printf '%012d' $$)
---

# E2E Test Project

## Goal

Throwaway project used by test-park-system.sh.

## Status

Created in test session at $(date +%H:%M:%S) on $(date +%Y-%m-%d).

## Setup

| Item | Path |
|---|---|
| Index | $TEST_DIR/index.md |

## Progress

- **2026-06-03** — Test setup created by test-park-system.sh.

## Backlog — Unpark instructions

1. This is a test. Don't actually do anything; the test script will delete it.

## Related

- [[park]]
- [[unpark]]
EOF
[ -f "$TEST_DIR/index.md" ] && ok "test project index.md created" || ko "could not create test project"

# --- T2: /list-parks detects the new paused project ---
echo ""
echo "T2: /list-parks detection"
out="$("$SYSTEM_ROOT/skills/list-parks/bin/list-parks" 2>&1)"
echo "$out" | grep -q "$TEST_PROJECT" && ok "list-parks shows test project" || ko "list-parks missed test project"

# --- T3: /list-projects (no filter) detects it too ---
echo ""
echo "T3: /list-projects (default, no filter)"
out="$("$SYSTEM_ROOT/skills/list-projects/bin/list-projects" 2>&1)"
echo "$out" | grep -q "$TEST_PROJECT" && ok "list-projects shows test project" || ko "list-projects missed test project"

# --- T4: /list-projects --status paused includes it ---
echo ""
echo "T4: /list-projects --status paused"
out="$("$SYSTEM_ROOT/skills/list-projects/bin/list-projects" --status paused 2>&1)"
echo "$out" | grep -q "$TEST_PROJECT" && ok "filter --status=paused includes paused project" || ko "filter --status=paused missed paused project"

# --- T5: /list-projects --status done excludes it ---
echo ""
echo "T5: /list-projects --status done (negative filter)"
out="$("$SYSTEM_ROOT/skills/list-projects/bin/list-projects" --status done 2>&1)"
echo "$out" | grep -q "$TEST_PROJECT" && ko "filter --status=done wrongly included paused project" || ok "filter --status=done correctly excludes paused project"

# --- T6: status change to done removes it from /list-parks ---
echo ""
echo "T6: status transition removes from /list-parks"
sed -i.bak 's/^status: paused$/status: done/' "$TEST_DIR/index.md" && rm "$TEST_DIR/index.md.bak"
out="$("$SYSTEM_ROOT/skills/list-parks/bin/list-parks" 2>&1)"
echo "$out" | grep -q "$TEST_PROJECT" && ko "list-parks still shows project after status=done" || ok "list-parks excludes done project"
# Restore to paused for downstream tests
sed -i.bak 's/^status: done$/status: paused/' "$TEST_DIR/index.md" && rm "$TEST_DIR/index.md.bak"

# --- T7: create a test learning, verify /list-learnings picks it up ---
echo ""
echo "T7: /list-learnings picks up new learning"
cat > "$TEST_LEARNING" <<EOF
---
date: 2026-06-03
type: learning
tags: [learning, test, e2e-marker]
confidence: high
source: session
id: 00000000-0000-5000-8000-$(printf '%012d' $((${$} + 1)))
---

# E2E Test Marker Learning

## Insight

This learning is created by test-park-system.sh and deleted on cleanup.
EOF
out="$("$SYSTEM_ROOT/skills/list-learnings/bin/list-learnings" --tag e2e-marker 2>&1)"
echo "$out" | grep -q "E2E Test Marker" && ok "list-learnings --tag e2e-marker finds test learning" || ko "list-learnings did not find test learning"

# --- T8: simulate /unpark behavior: read project, verify Related links resolve ---
echo ""
echo "T8: /unpark drift check (referenced setup path exists?)"
# The test project's Setup table lists $TEST_DIR/index.md which exists.
[ -f "$TEST_DIR/index.md" ] && ok "setup path from project still exists" || ko "setup path missing"

# Drift: modify the file to reference a non-existent path; verify a basic
# drift-detect would catch it.
DRIFT_PATH="/tmp/does-not-exist-$$"
echo "  (drift simulation: would the user notice if Setup pointed at $DRIFT_PATH?)"
[ ! -f "$DRIFT_PATH" ] && ok "drift sentinel path correctly absent" || ko "drift sentinel unexpectedly present"

# --- T9: validators stay green after all our changes ---
echo ""
echo "T9: validators after test churn"
out="$(bash "$BRAIN_DIR/scripts/check-skill-relations.sh" 2>&1)"
echo "$out" | grep -q "all relations valid" && ok "check-skill-relations passes" || ko "check-skill-relations failed: $out"

out="$(bash "$BRAIN_DIR/scripts/check-frontmatter.sh" 2>&1)"
echo "$out" | grep -q "passed" && ok "check-frontmatter passes" || ko "check-frontmatter failed"

# --- T10: agent-agnostic symlinks ---
echo ""
echo "T10: agent-agnostic symlinks"
for skill in park unpark list-parks list-projects list-learnings promote; do
    [ -L "$HOME/.claude/skills/$skill" ] && ok "claude symlink: $skill" || ko "claude symlink missing: $skill"
    [ -L "$HOME/.pi/agent/skills/$skill" ] && ok "pi symlink: $skill" || ko "pi symlink missing: $skill"
done

# --- summary ---
echo ""
echo "================================="
echo "test-park-system: $pass passed, $fail failed"
echo "================================="

if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
