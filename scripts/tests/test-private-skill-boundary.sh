#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Reject private files under public system/ at the commit/push privacy gate.
set -euo pipefail

scan="$(cd "$(dirname "$0")/../.." && pwd)/scripts/privacy-scan.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
git config user.name Test
git config user.email test@example.invalid
mkdir -p system/skills/demo vault/skills
printf 'private rules\n' > vault/skills/demo.private.md
printf 'public rules\n' > system/skills/demo/SKILL.md
git add .
bash "$scan" --staged >/dev/null

git commit -qm initial
for path in system/skills/demo.private.md system/skills/demo/.private.md system/skills/demo.private/note.md; do
  mkdir -p "$(dirname "$path")"
  printf 'private rules\n' > "$path"
  git add "$path"
  if bash "$scan" --staged >"$tmp/output" 2>&1; then
    echo "FAIL: accepted $path under system/" >&2
    exit 1
  fi
  grep -q "$path" "$tmp/output"
  if bash "$scan" tracked >"$tmp/output" 2>&1; then
    echo "FAIL: tracked scan accepted $path under system/" >&2
    exit 1
  fi
  git reset -q -- "$path"
  rm -f "$path"
done
bash "$scan" --staged >/dev/null
echo 'Private skill boundary passed.'
