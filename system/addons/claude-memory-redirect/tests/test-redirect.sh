#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Behavioural tests for claude-memory-redirect. Runs against a tmpdir vault AND a
# tmpdir $HOME (fake ~/.claude/projects) — no real memory dirs, no network, no
# install. Covers: migrate frontmatter normalization, symlink redirect, the loud
# uuid5 failure path, and uninstall --restore round-trip.
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
	echo "SKIP: python3 not installed — claude-memory-redirect needs it" >&2
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

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Build a fake vault that owns the addon scripts + a real uuid5-gen.sh + namespace.
VAULT="$TEST_DIR/vault"
FAKE_ADDON="$VAULT/system/addons/claude-memory-redirect"
mkdir -p "$FAKE_ADDON" "$VAULT/scripts" "$VAULT/vault/memories/projects"
cp "$ADDON_DIR"/*.sh "$FAKE_ADDON/"
cp "$ADDON_DIR"/config.default.json "$FAKE_ADDON/"
# Bring along the real uuid5-gen.sh so migrate produces genuine ids.
cp "$(cd "$ADDON_DIR/../../.." && pwd)/scripts/uuid5-gen.sh" "$VAULT/scripts/"
# uuid5-gen.sh needs a vault namespace; copy brain.json if present, else seed one.
if [ -f "$(cd "$ADDON_DIR/../../.." && pwd)/brain.json" ]; then
	cp "$(cd "$ADDON_DIR/../../.." && pwd)/brain.json" "$VAULT/"
else
	echo '{ "namespace": "e37d107c-934a-4626-806e-8da1b442c8e4" }' > "$VAULT/brain.json"
fi

MIGRATE="$FAKE_ADDON/claude-memory-migrate.sh"
SYMLINK="$FAKE_ADDON/claude-memory-symlink.sh"
UNINSTALL="$FAKE_ADDON/uninstall.sh"

# Fake $HOME with one Claude project that has a memory dir + one note.
FAKE_HOME="$TEST_DIR/home"
ENCODED="-tmp-myproj"
PROJECT="$FAKE_HOME/.claude/projects/$ENCODED"
mkdir -p "$PROJECT/memory"
cat > "$PROJECT/memory/note.md" <<'EOF'
# A remembered fact
The user prefers tabs.
EOF
# slug.sh reads cwd from a transcript jsonl; give it one so the slug is deterministic.
echo '{"cwd":"/tmp/myproj"}' > "$PROJECT/session.jsonl"

# --- migrate: normalizes frontmatter + gives the note a real id ---
HOME="$FAKE_HOME" bash "$MIGRATE" "$PROJECT" >/dev/null 2>&1
MIGRATED="$VAULT/vault/memories/projects/myproj/note.md"
assert "migrate wrote the note into agentBrain" "$([ -f "$MIGRATED" ] && echo yes || echo no)" "yes"
assert "migrated note has a uuid id" "$(grep -cE '^id: [0-9a-f-]{36}$' "$MIGRATED")" "1"
assert "migrated note has type frontmatter" "$(grep -c '^type:' "$MIGRATED")" "1"

# --- symlink: replaces the memory dir with a link into agentBrain, backs up original ---
HOME="$FAKE_HOME" bash "$SYMLINK" "$PROJECT" >/dev/null 2>&1
assert "memory dir is now a symlink" "$([ -L "$PROJECT/memory" ] && echo yes || echo no)" "yes"
linktarget="$(readlink "$PROJECT/memory")"
assert "symlink points into agentBrain" "$(printf '%s' "$linktarget" | grep -cE '(vault|local)/memories/projects')" "1"
assert "original memory dir was backed up" "$(find "$PROJECT" -maxdepth 1 -type d -name '.memory-pre-redirect-backup-*' | wc -l | tr -d ' ')" "1"

# --- uninstall --restore: removes the link and puts the original back ---
HOME="$FAKE_HOME" bash "$UNINSTALL" --restore >/dev/null 2>&1
assert "uninstall removed the symlink" "$([ -L "$PROJECT/memory" ] && echo yes || echo no)" "no"
assert "uninstall restored a real dir" "$([ -d "$PROJECT/memory" ] && echo yes || echo no)" "yes"
assert "restored dir has the original note" "$([ -f "$PROJECT/memory/note.md" ] && echo yes || echo no)" "yes"
assert "restore consumed the backup dir" "$(find "$PROJECT" -maxdepth 1 -type d -name '.memory-pre-redirect-backup-*' | wc -l | tr -d ' ')" "0"
# idempotent
rc=0; HOME="$FAKE_HOME" bash "$UNINSTALL" >/dev/null 2>&1 || rc=$?
assert "uninstall is idempotent (exit 0)" "$rc" "0"

# --- loud uuid5 failure: a broken uuid5-gen aborts migrate (exit 1), no id-less note ---
BROKEN_VAULT="$TEST_DIR/broken"
BV_ADDON="$BROKEN_VAULT/system/addons/claude-memory-redirect"
mkdir -p "$BV_ADDON" "$BROKEN_VAULT/scripts" "$BROKEN_VAULT/vault/memories/projects"
cp "$ADDON_DIR"/*.sh "$BV_ADDON/"
cp "$ADDON_DIR"/config.default.json "$BV_ADDON/"
# Broken generator: prints nothing, exits non-zero.
printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 1\n' > "$BROKEN_VAULT/scripts/uuid5-gen.sh"
chmod +x "$BROKEN_VAULT/scripts/uuid5-gen.sh"
BV_HOME="$TEST_DIR/bhome"
BV_PROJECT="$BV_HOME/.claude/projects/-tmp-bp"
mkdir -p "$BV_PROJECT/memory"
printf '# no id here\nbody\n' > "$BV_PROJECT/memory/x.md"
echo '{"cwd":"/tmp/bp"}' > "$BV_PROJECT/session.jsonl"
rc=0
err="$(HOME="$BV_HOME" bash "$BV_ADDON/claude-memory-migrate.sh" "$BV_PROJECT" 2>&1 >/dev/null)" || rc=$?
assert "broken uuid5-gen aborts migrate (exit 1)" "$rc" "1"
assert "uuid5 failure is loud" "$(printf '%s' "$err" | grep -c 'FAILED to generate a UUID5')" "1"
assert "no id-less note was written" "$([ -f "$BROKEN_VAULT/vault/memories/projects/bp/x.md" ] && echo yes || echo no)" "no"

# ---- report ----
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
	printf '%s\n' "${failures[@]}" >&2
	exit 1
fi
