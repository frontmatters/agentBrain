#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-session-digest.sh — unit tests for scripts/session-digest.sh.
# Verifies: per-session digest rows for Claude Code and Pi formats, corrupt-line
# tolerance, --min-turns filter, and aggregated skill usage.
# shellcheck disable=SC2015  # `assert && pass || fail` is the intended test-assert idiom here

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-session-digest-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

PASS=0
FAIL=0
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }

# --- Claude Code fixture: project dir + 1 sessie ---
CC_DIR="$FIXTURE/claude-projects/-Users-test-Developer-myproj"
mkdir -p "$CC_DIR"
cat > "$CC_DIR/session-1.jsonl" <<'EOF'
{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>meta</local-command-caveat>"}}
{"type":"user","message":{"role":"user","content":"fix the login bug\nsecond line"}}
{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5","content":[{"type":"tool_use","name":"Read","input":{}},{"type":"tool_use","name":"Skill","input":{"skill":"save-learning"}},{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:brainstorming"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"boom"}]}}
{"type":"user","message":{"role":"user","content":"try again"}}
THIS LINE IS NOT JSON
{"type":"assistant","isSidechain":true,"message":{"role":"assistant","model":"claude-haiku-4-5","content":[]}}
EOF

# Sessie onder de --min-turns drempel (1 echte user turn)
cat > "$CC_DIR/session-2.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"tiny"}}
EOF

# --- Pi fixture ---
PI_DIR="$FIXTURE/pi-sessions/--Users-test-Developer-otherproj--"
mkdir -p "$PI_DIR"
cat > "$PI_DIR/2026-07-06T06-46-43-225Z_abc.jsonl" <<'EOF'
{"type":"session","version":3,"id":"abc","timestamp":"2026-07-06T06:46:43.225Z","cwd":"/tmp/fixture/otherproj"}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"check the brain projects map"}]}}
{"type":"message","message":{"role":"assistant","model":"glm-5.2","content":[{"type":"toolCall","name":"bash","arguments":{}}]}}
{"type":"message","message":{"role":"toolResult","isError":true,"toolName":"bash","content":[]}}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"ok now fix it"}]}}
EOF

run_digest() {
	CLAUDE_PROJECTS_DIR="$FIXTURE/claude-projects" \
	PI_SESSIONS_DIR="$FIXTURE/pi-sessions" \
	bash "$ROOT_DIR/scripts/session-digest.sh" --format tsv "$@"
}

# Case 1: draait zonder fout, corrupt line is niet fataal
if OUT="$(run_digest 2>/dev/null)"; then pass "runs despite corrupt line"; else fail "script failed"; fi

# Case 2: Claude-sessie 1 rij met juiste velden
ROW="$(printf '%s\n' "$OUT" | grep "session-1" || true)"
if [ -n "$ROW" ]; then pass "claude session row present"; else fail "claude session row missing"; fi
echo "$ROW" | grep -q "myproj" && pass "project extracted" || fail "project missing"
echo "$ROW" | awk -F'\t' '{exit ($5==2)?0:1}' && pass "2 real user turns (meta+tool_result skipped)" || fail "turn count wrong: $ROW"
echo "$ROW" | grep -q "claude-fable-5" && pass "model captured" || fail "model missing"
echo "$ROW" | grep -q "Skill:2" && pass "tool counts captured" || fail "tool counts missing"
echo "$ROW" | grep -q "save-learning" && pass "skill invocation captured" || fail "skill missing"
echo "$ROW" | grep -q "fix the login bug" && pass "first prompt captured" || fail "first prompt wrong"
echo "$ROW" | grep -qv "second line" && pass "only first line of prompt" || fail "prompt leaked extra lines"
echo "$ROW" | awk -F'\t' '{exit ($9==1)?0:1}' && pass "error counted" || fail "error count wrong"
echo "$ROW" | awk -F'\t' '{exit ($10==1)?0:1}' && pass "sidechain counted" || fail "sidechain count wrong"

# Case 3: --min-turns filtert session-2 (1 turn) weg bij default 2
printf '%s\n' "$OUT" | grep -q "session-2" && fail "min-turns filter failed" || pass "min-turns filters small session"
OUT_ALL="$(run_digest --min-turns 1 2>/dev/null)"
printf '%s\n' "$OUT_ALL" | grep -q "session-2" && pass "--min-turns 1 includes small session" || fail "--min-turns 1 broken"

# Case 4: Pi-sessie rij aanwezig met toolResult-error
PIROW="$(printf '%s\n' "$OUT" | grep "otherproj" || true)"
if [ -n "$PIROW" ]; then pass "pi session row present"; else fail "pi session row missing"; fi
echo "$PIROW" | grep -q "glm-5.2" && pass "pi model captured" || fail "pi model missing"
echo "$PIROW" | grep -q "bash:1" && pass "pi toolCall counted" || fail "pi toolCall missing"
echo "$PIROW" | awk -F'\t' '{exit ($9==1)?0:1}' && pass "pi toolResult error counted" || fail "pi error count wrong"

# Case 5: md-format bevat aggregatie-sectie voor skill-gebruik
OUT_MD="$(CLAUDE_PROJECTS_DIR="$FIXTURE/claude-projects" PI_SESSIONS_DIR="$FIXTURE/pi-sessions" bash "$ROOT_DIR/scripts/session-digest.sh" --format md 2>/dev/null)"
echo "$OUT_MD" | grep -q "## Skill usage" && pass "md has skill aggregation" || fail "md aggregation missing"
echo "$OUT_MD" | grep -q "save-learning" && pass "aggregation counts skill" || fail "aggregation misses skill"
echo "$OUT_MD" | grep -q -- "- superpowers:brainstorming: 1" && pass "namespaced skill aggregated intact" || fail "namespaced skill mangled in aggregation"

echo
echo "session-digest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
