#!/usr/bin/env bash
# test-spaces-seal.sh — proves local/spaces/ is sealed out of the personal sync.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"

git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "SKIP test-spaces-seal: local/ is not a git repo"; exit 0; }

# 1) gitignore must ignore spaces/
git -C "$LOCAL_DIR" check-ignore -q spaces/ || { echo "FAIL: spaces/ not gitignored"; exit 1; }

# 2) a planted fact in a space must NOT appear in 'git add -A --dry-run'
TS="$(date +%s)"
PLANT="$LOCAL_DIR/spaces/__sealtest__/note-$TS.md"
mkdir -p "$(dirname "$PLANT")"
printf -- '---\ntype: learning\n---\nseal probe %s\n' "$TS" > "$PLANT"
staged="$(git -C "$LOCAL_DIR" add -A --dry-run 2>/dev/null | grep -F "spaces/__sealtest__" || true)"
rm -rf "$LOCAL_DIR/spaces/__sealtest__"
[ -z "$staged" ] || { echo "FAIL: space content would be staged by sync: $staged"; exit 1; }

echo "PASS test-spaces-seal"
