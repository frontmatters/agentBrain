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

# Composite profile: the same rule, lanes read from framework.dev/next/live.
C="$TMP/composite"; mkdir -p "$C/dev" "$C/live"
g() { git -C "$1" -c user.name=Test -c user.email=test@example.invalid "${@:2}"; }
git -C "$C/dev" init -q -b main
printf 'a\n' > "$C/dev/app.txt"; printf 'dev only\n' > "$C/dev/release-tool.sh"; printf 'spec\n' > "$C/dev/spec-ping.md"
g "$C/dev" add . && g "$C/dev" commit -q -m base
SRC="$(git -C "$C/dev" rev-parse HEAD)"
git -C "$C/dev" worktree add -q -b next "$C/next"
# Live is a published copy with its own history: the deploy leaves release-tool.sh out.
git -C "$C/live" init -q -b main
cp "$C/dev/app.txt" "$C/live/"; cp "$C/dev/spec-ping.md" "$C/live/SPEC-ping.md"
g "$C/live" add . && g "$C/live" commit -q -m deploy
printf '{"profile":"composite","framework":{"dev":"%s/dev","next":"%s/next","live":"%s/live"},"releases":{"root":"%s/rel"}}\n' "$C" "$C" "$C" "$C" > "$C/factory.json"
CCHECK=(bash "$HERE/factory-lane-origin.sh" "$C")
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: separate live repo passed without a policy' >&2; exit 1; fi
grep -q 'different repositories' "$TMP/out"
jq '.lanePolicy = {"live": "separate-repo"}' "$C/factory.json" > "$C/f.new" && mv "$C/f.new" "$C/factory.json"
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: live without a recorded source passed' >&2; exit 1; fi
grep -q 'does not record its source commit' "$TMP/out"
git -C "$C/live" config factory.sourceCommit "$SRC"
# A file the deploy leaves out may be missing; a case-only rename counts as equal.
"${CCHECK[@]}" | grep -q 'PASS (live = '
# A change made only in live fails.
printf 'hotfix\n' >> "$C/live/app.txt"; g "$C/live" commit -q -am 'live-only hotfix'
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: live-only change passed' >&2; exit 1; fi
grep -q 'differ from its source commit' "$TMP/out"; grep -q 'app.txt' "$TMP/out"
g "$C/live" reset -q --hard HEAD~1
# A file that exists only in live fails.
printf 'x\n' > "$C/live/extra.txt"; g "$C/live" add extra.txt && g "$C/live" commit -q -m extra
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: live-only file passed' >&2; exit 1; fi
grep -q 'extra.txt' "$TMP/out"
g "$C/live" reset -q --hard HEAD~1
"${CCHECK[@]}" | grep -q 'PASS (live = '
# A source commit that next cannot reach fails.
git -C "$C/dev" switch -q -c side; g "$C/dev" commit -q --allow-empty -m side
git -C "$C/live" config factory.sourceCommit "$(git -C "$C/dev" rev-parse HEAD)"
git -C "$C/dev" switch -q main
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: unreachable source commit passed' >&2; exit 1; fi
grep -q 'not reachable from next' "$TMP/out"
git -C "$C/live" config factory.sourceCommit 0123456789abcdef0123456789abcdef01234567
if "${CCHECK[@]}" > "$TMP/out" 2>&1; then echo 'FAIL: unknown source commit passed' >&2; exit 1; fi
grep -q 'not in the dev repository' "$TMP/out"
echo 'factory lane origin: PASS'
