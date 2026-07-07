#!/usr/bin/env bash
# Behavioural tests for session-journal. Runs against a tmpdir BRAIN_ROOT — no
# real local/, no network, no Claude install. Covers: transcript parse roundtrip,
# manual /journal save, loud corrupt-config handling, and uninstall hook removal.
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
	echo "SKIP: python3 not installed — session-journal needs it" >&2
	exit 0
fi

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

# Build a throwaway BRAIN_ROOT that mirrors the structure journal-update expects:
# <root>/system/addons/session-journal/<scripts> and <root>/local/sessions.
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FAKE_ADDON="$TEST_DIR/system/addons/session-journal"
mkdir -p "$FAKE_ADDON" "$TEST_DIR/local/sessions"
cp "$ADDON_DIR"/*.sh "$FAKE_ADDON/"
cp "$ADDON_DIR"/config.default.json "$FAKE_ADDON/"

UPDATE="$FAKE_ADDON/journal-update.sh"
SAVE="$FAKE_ADDON/journal-save.sh"
JOURNAL="$TEST_DIR/local/sessions/session-journal.md"
LOCAL_CONFIG="$TEST_DIR/local/sessions/journal-config.json"

# --- transcript parse roundtrip ---
TRANSCRIPT="$TEST_DIR/transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","cwd":"/work/myproj","message":{"content":[{"type":"text","text":"Build the thing"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/work/myproj/foo.py"}},{"type":"text","text":"Done writing foo.py"}]}}
EOF

bash "$UPDATE" --transcript "$TRANSCRIPT" --source manual >/dev/null 2>&1
assert "journal file created" "$([ -f "$JOURNAL" ] && echo yes || echo no)" "yes"
assert "project inferred from cwd basename" "$(grep -c '### Project: myproj' "$JOURNAL")" "1"
assert "task line from last user message" "$(grep -c 'Build the thing' "$JOURNAL")" "1"
assert "changed file recorded (relative path)" "$(grep -c '`foo.py`' "$JOURNAL")" "1"

# --- manual /journal save appends an open question ---
bash "$SAVE" --note "remember the edge case" >/dev/null 2>&1
assert "manual note appended" "$(grep -c 'remember the edge case' "$JOURNAL")" "1"

# --- idempotent rewrite preserves the frontmatter id ---
python3 - "$JOURNAL" <<'PYEOF'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'^id:.*$','id: keep-me-123',s,count=1,flags=re.M)
open(p,'w').write(s)
PYEOF
bash "$UPDATE" --transcript "$TRANSCRIPT" --source autosave >/dev/null 2>&1
assert "rewrite preserves frontmatter id" "$(grep -c '^id: keep-me-123' "$JOURNAL")" "1"

# --- loud corrupt-config handling ---
printf '{ this is not json' > "$LOCAL_CONFIG"
# manual source must abort loudly (exit 2) and say so on stderr
rc=0; err="$(bash "$UPDATE" --transcript "$TRANSCRIPT" --source manual 2>&1 >/dev/null)" || rc=$?
assert "manual run aborts on corrupt config (exit 2)" "$rc" "2"
assert "corrupt config error is loud on stderr" "$(printf '%s' "$err" | grep -c 'not valid JSON')" "1"
# hook source must NOT block: exit 0, but still warns + falls back to default
rc=0; out="$(bash "$UPDATE" --transcript "$TRANSCRIPT" --source autosave 2>&1)" || rc=$?
assert "hook run tolerates corrupt config (exit 0)" "$rc" "0"
assert "hook run warns about fallback" "$(printf '%s' "$out" | grep -c 'falling back to default')" "1"
rm -f "$LOCAL_CONFIG"

# --- uninstall removes our hooks from a fake settings.json ---
FAKE_HOME="$TEST_DIR/fakehome"
mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "bash ~/agentBrain/system/addons/session-journal/claude-stop-hook.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "bash ~/agentBrain/system/addons/session-journal/claude-autosave-hook.sh" }, { "type": "command", "command": "bash /some/other/hook.sh" } ] } ]
  }
}
EOF
HOME="$FAKE_HOME" bash "$FAKE_ADDON/uninstall.sh" >/dev/null 2>&1
assert "uninstall removed stop hook" "$(grep -c 'claude-stop-hook' "$FAKE_HOME/.claude/settings.json")" "0"
assert "uninstall removed autosave hook" "$(grep -c 'claude-autosave-hook' "$FAKE_HOME/.claude/settings.json")" "0"
assert "uninstall kept unrelated hook" "$(grep -c '/some/other/hook.sh' "$FAKE_HOME/.claude/settings.json")" "1"
# idempotent second run
rc=0; HOME="$FAKE_HOME" bash "$FAKE_ADDON/uninstall.sh" >/dev/null 2>&1 || rc=$?
assert "uninstall is idempotent (exit 0)" "$rc" "0"

# ---- report ----
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
	printf '%s\n' "${failures[@]}" >&2
	exit 1
fi
