#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-spaces-seal.sh — proves local/spaces/ is sealed out of the personal sync.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT_DIR/scripts/lib/vault.sh"
LOCAL_DIR="$VAULT_DIR"

git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1 || { echo "SKIP test-spaces-seal: local/ is not a git repo"; exit 0; }

# 1) space CONTENT must be invisible to the vault repo. Asserting on the literal
# rule would fail the moment it changes shape, and it has: `spaces/` became
# `spaces/*` plus `!spaces/.gitignore`, so the fail-closed file can itself be
# tracked. What matters is the behaviour, so test that instead of the text.
git -C "$LOCAL_DIR" check-ignore -q spaces/any-space/note.md \
	|| { echo "FAIL: space content is not gitignored by the vault"; exit 1; }
# 1b) and the fail-closed file must NOT be ignored: a layer that cannot be
# committed does not survive a fresh clone, which is where it matters most.
if [ -f "$LOCAL_DIR/spaces/.gitignore" ]; then
	git -C "$LOCAL_DIR" check-ignore -q spaces/.gitignore \
		&& { echo "FAIL: spaces/.gitignore is itself ignored, so it never ships"; exit 1; }
fi

# 2) a planted fact in a space must NOT appear in 'git add -A --dry-run'
TS="$(date +%s)"
PLANT="$LOCAL_DIR/spaces/__sealtest__/note-$TS.md"
mkdir -p "$(dirname "$PLANT")"
printf -- '---\ntype: learning\n---\nseal probe %s\n' "$TS" > "$PLANT"
staged="$(git -C "$LOCAL_DIR" add -A --dry-run 2>/dev/null | grep -F "spaces/__sealtest__" || true)"
rm -rf "$LOCAL_DIR/spaces/__sealtest__"
[ -z "$staged" ] || { echo "FAIL: space content would be staged by sync: $staged"; exit 1; }

echo "PASS test-spaces-seal"
