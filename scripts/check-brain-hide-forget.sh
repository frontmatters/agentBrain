#!/usr/bin/env bash
# check-brain-hide-forget.sh — E2E smoke test for brain-hide-forget skill set.
# Part of the agentBrain doctor-suite.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

echo "check-brain-hide-forget: verifying installation"

# Skill bins + manifests
for skill in brain-hide brain-unhide brain-forget brain-recall list-hidden; do
    bin="$ROOT_DIR/system/skills/$skill/bin/$skill"
    if [ -x "$bin" ]; then
        ok "$skill bin exists + executable"
    else
        bad "$skill bin missing or not executable: $bin"
    fi
    if [ -f "$ROOT_DIR/system/skills/$skill/SKILL.md" ]; then
        ok "$skill SKILL.md exists"
    else
        bad "$skill SKILL.md missing"
    fi
done

# visibility.sh
if [ -f "$ROOT_DIR/system/lib/visibility.sh" ]; then
    ok "visibility.sh exists"
else
    bad "visibility.sh missing"
fi

# E2E flow in fixture brain
echo ""
echo "check-brain-hide-forget: E2E flow"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

mkdir -p "$TMPD/local/learnings" "$TMPD/system/lib"
cp "$ROOT_DIR/system/lib/visibility.sh" "$TMPD/system/lib/"

for slug in keep hide forget; do
    cat > "$TMPD/local/learnings/$slug.md" <<EOF
---
date: 2026-06-03
type: learning
tags: [test]
id: 00000000-0000-0000-0000-000000000000
---

# $slug
EOF
done

# Hide
BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/brain-hide/bin/brain-hide" learnings/hide
if grep -q "^hidden: true$" "$TMPD/local/learnings/hide.md"; then
    ok "brain-hide adds flag"
else
    bad "brain-hide failed"
fi

# Forget
BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/brain-forget/bin/brain-forget" learnings/forget --force
if [ ! -f "$TMPD/local/learnings/forget.md" ]; then
    ok "brain-forget removes file"
else
    bad "brain-forget left file"
fi
trashed=$(find "$TMPD/local/.trash/forget" -name "forget.md" | head -1)
if [ -n "$trashed" ]; then
    ok "brain-forget moves to trash"
else
    bad "brain-forget did not trash"
fi

# list-hidden shows both
out=$(BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/list-hidden/bin/list-hidden" --include-trash 2>&1)
if echo "$out" | grep -q "hide.md"; then
    ok "list-hidden shows hidden"
else
    bad "list-hidden missed hidden"
fi
if echo "$out" | grep -q "forget.md"; then
    ok "list-hidden --include-trash shows trashed path"
else
    bad "list-hidden trash section incorrect: $(echo "$out" | head -20)"
fi

# CRITICAL: verify trash section shows original path, NOT timestamp
if echo "$out" | grep -qE "2026-06-03T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"; then
    bad "list-hidden leaks ISO timestamp as path"
else
    ok "list-hidden filters ISO timestamp"
fi

# Unhide
BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/brain-unhide/bin/brain-unhide" learnings/hide
flags=$(grep -c "^hidden:" "$TMPD/local/learnings/hide.md" || true)
if [ "$flags" -eq 0 ]; then
    ok "brain-unhide removes flag"
else
    bad "brain-unhide left $flags hidden lines"
fi

# Recall by timestamp (use globbing — portable across BSD/GNU find)
TS=""
for d in "$TMPD/local/.trash/forget"/*/; do
    [ -d "$d" ] || continue
    TS=$(basename "$d")
    break
done
BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/brain-recall/bin/brain-recall" "$TS"
if [ -f "$TMPD/local/learnings/forget.md" ]; then
    ok "brain-recall restores file"
else
    bad "brain-recall did not restore"
fi

# keep.md untouched
if [ -f "$TMPD/local/learnings/keep.md" ]; then
    ok "keep.md untouched"
else
    bad "keep.md modified"
fi

# Safety: refuse system/
mkdir -p "$TMPD/system/skills/x"
echo "" > "$TMPD/system/skills/x/SKILL.md"
set +e
BRAIN_DIR="$TMPD" bash "$ROOT_DIR/system/skills/brain-hide/bin/brain-hide" system/skills/x 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 3 ]; then
    ok "safety refuses system/"
else
    bad "safety failed (rc=$rc)"
fi

echo ""
echo "check-brain-hide-forget: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
