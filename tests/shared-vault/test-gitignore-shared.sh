#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# The `shared/` dir + `/shared` symlink must be ignored by the framework git.
# Test the entry itself (robust whether or not a live `shared/` symlink exists — a path
# THROUGH a live symlink errors with "beyond a symbolic link", which is not what we mean).
git check-ignore -q shared || { echo "FAIL: shared/ niet genegeerd"; exit 1; }
# Belt-and-braces against a real symlink: it must never surface as tracked/untracked.
[ -z "$(git status --porcelain -- shared 2>/dev/null)" ] || { echo "FAIL: shared/ verschijnt in git status"; exit 1; }
# When no live symlink is present, a nested path must also match the rule.
if [ ! -L shared ]; then
	git check-ignore -q shared/anything.md || { echo "FAIL: shared/ contents niet genegeerd"; exit 1; }
fi
echo "PASS test-gitignore-shared"
