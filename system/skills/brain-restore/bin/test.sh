#!/usr/bin/env bash
# Smoke test for brain-restore MVP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTORE="$SCRIPT_DIR/brain-restore"
EXTRACT_FIXTURE="$SCRIPT_DIR/../../brain-extract/fixtures/minimal-vault"
EXTRACT="$SCRIPT_DIR/../../brain-extract/bin/brain-extract"

# Snapshot original fixture
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp -r "$EXTRACT_FIXTURE" "$WORK/vault"
cd "$WORK"

# Extract
mkdir project
cd project
"$EXTRACT" --vault "$WORK/vault" --keep demo-project >/dev/null

# Remove original vault content to simulate fresh restore target
rm -rf "$WORK/vault/projects/demo-project" "$WORK/vault/learnings/Demo-Learning.md"

# Restore
"$RESTORE" --vault "$WORK/vault" .brain-package >/dev/null

# Verify
[ -f "$WORK/vault/projects/demo-project/index.md" ] || { echo "FAIL: project not restored"; exit 1; }
[ -f "$WORK/vault/learnings/Demo-Learning.md" ] || { echo "FAIL: learning not restored"; exit 1; }

echo "PASS: brain-restore MVP smoke"
