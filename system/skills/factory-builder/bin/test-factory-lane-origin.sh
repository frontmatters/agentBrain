#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/factory/dev" "$TMP/factory/next" "$TMP/factory/live"
# Next starts as a worktree of dev; no global git identity is needed.
git -C "$TMP/factory/dev" init -q
git -C "$TMP/factory/dev" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m base
git -C "$TMP/factory/dev" worktree add -q -b candidate "$TMP/factory/next"
git -C "$TMP/factory/dev" worktree add -q -b live "$TMP/factory/live"
printf '{"lanes":{"dev":"%s/factory/dev","next":"%s/factory/next","live":"%s/factory/live"}}\n' "$TMP" "$TMP" "$TMP" > "$TMP/factory/factory.json"
CHECK=(bash "$HERE/factory-lane-origin.sh" "$TMP/factory")
"${CHECK[@]}" | grep -q 'PASS'
printf 'dirty\n' > "$TMP/factory/next/new.txt"
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: dirty next passed' >&2; exit 1; fi
grep -q 'next has uncommitted changes' "$TMP/out"
rm "$TMP/factory/next/new.txt"
git -C "$TMP/factory/next" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m 'next-only'
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: next-only commit passed' >&2; exit 1; fi
grep -q 'FAIL' "$TMP/out"
git -C "$TMP/factory/dev" merge -q --ff-only candidate
"${CHECK[@]}" | grep -q 'PASS'
# A live-only hotfix must reach next, then dev, before the chain is green.
git -C "$TMP/factory/live" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m 'live-hotfix'
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: live-only commit passed' >&2; exit 1; fi
grep -q 'live has commits' "$TMP/out"
git -C "$TMP/factory/next" -c user.name=Test -c user.email=test@example.invalid merge -q --no-edit live
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: hotfix missing from dev passed' >&2; exit 1; fi
grep -q 'next has commits' "$TMP/out"
git -C "$TMP/factory/dev" merge -q --ff-only candidate
"${CHECK[@]}" | grep -q 'PASS'
printf 'dirty\n' > "$TMP/factory/live/new.txt"
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: dirty live passed' >&2; exit 1; fi
grep -q 'live has uncommitted changes' "$TMP/out"
rm "$TMP/factory/live/new.txt"
"${CHECK[@]}" | grep -q 'PASS'
git -C "$TMP/factory/live" switch -q --detach
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: detached live passed' >&2; exit 1; fi
grep -q 'live is detached' "$TMP/out"
git -C "$TMP/factory/live" switch -q live
mkdir "$TMP/unrelated"
git -C "$TMP/unrelated" init -q
git -C "$TMP/unrelated" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m unrelated
jq --arg path "$TMP/unrelated" '.lanes.live = $path' "$TMP/factory/factory.json" > "$TMP/factory/config.new"
mv "$TMP/factory/config.new" "$TMP/factory/factory.json"
if "${CHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: unrelated repo passed' >&2; exit 1; fi
grep -q 'different repositories' "$TMP/out"
echo 'factory lane origin: PASS'
