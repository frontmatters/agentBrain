#!/usr/bin/env bash
# Keep the complete promotion chain: live HEAD in next, next HEAD in dev.
# Lanes come from the shared profile normalizer, so standard and composite
# factories are checked by the same rule. A live lane that is a separate
# repository (a published copy) is only accepted when factory.json says so with
# "lanePolicy": {"live": "separate-repo"}. The deploy then records the dev
# commit it copied (git config factory.sourceCommit in the live checkout); that
# commit must be reachable from next, and every file live tracks must match it,
# so a change made only in live still fails. Files the deploy leaves out may be
# missing from live; case-only path differences count as equal.
set -euo pipefail
FACTORY="${1:?usage: factory-lane-origin.sh FACTORY_PATH}"
FACTORY="$(cd "$FACTORY" && pwd -P)"
CONFIG="$FACTORY/factory.json"
command -v jq >/dev/null || { echo 'factory-lane-origin: jq required' >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "factory-lane-origin: missing $CONFIG" >&2; exit 2; }
PROFILE_BIN="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/factory-profile.py"
LANES="$(python3 "$PROFILE_BIN" "$FACTORY")" || exit 2
LIVE_POLICY="$(jq -r '.lanePolicy.live // empty' "$CONFIG")"
paths=()
for lane in dev next live; do
  p="$(printf '%s' "$LANES" | jq -er --arg lane "$lane" '.lanes[$lane] | select(type == "string" and length > 0)')" || {
    echo "factory-lane-origin: missing $lane lane" >&2; exit 2;
  }
  [ -d "$p" ] || { echo "factory-lane-origin: missing $lane lane: $p" >&2; exit 2; }
  paths+=("$p")
done
DEV="${paths[0]}" NEXT="${paths[1]}" LIVE="${paths[2]}"
for p in "$DEV" "$NEXT" "$LIVE"; do
  git -C "$p" rev-parse --verify HEAD >/dev/null || { echo "factory-lane-origin: invalid git lane: $p" >&2; exit 2; }
done
for lane in next live; do
  case "$lane" in next) p="$NEXT" ;; live) p="$LIVE" ;; esac
  [ -n "$(git -C "$p" branch --show-current)" ] || { echo "factory-lane-origin: FAIL — $lane is detached" >&2; exit 1; }
  [ -z "$(git -C "$p" status --porcelain)" ] || { echo "factory-lane-origin: FAIL — $lane has uncommitted changes" >&2; exit 1; }
done
# Commit hashes alone do not establish that these are lanes of the same repo.
dev_git="$(cd "$(git -C "$DEV" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)"
next_git="$(cd "$(git -C "$NEXT" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)"
live_git="$(cd "$(git -C "$LIVE" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)"
[ "$dev_git" = "$next_git" ] || { echo 'factory-lane-origin: lanes are different repositories' >&2; exit 1; }
if [ "$next_git" != "$live_git" ]; then
  [ "$LIVE_POLICY" = "separate-repo" ] || { echo 'factory-lane-origin: lanes are different repositories' >&2; exit 1; }
  src="$(git -C "$LIVE" config --get factory.sourceCommit || true)"
  [ -n "$src" ] || { echo 'factory-lane-origin: FAIL — separate-repo live does not record its source commit (git config factory.sourceCommit); deploy it again' >&2; exit 1; }
  git -C "$NEXT" cat-file -e "$src^{commit}" 2>/dev/null || { echo "factory-lane-origin: FAIL — live was deployed from ${src:0:12}, which is not in the dev repository" >&2; exit 1; }
  if ! git -C "$NEXT" merge-base --is-ancestor "$src" HEAD; then
    echo "factory-lane-origin: FAIL — live was deployed from ${src:0:12}, which is not reachable from next" >&2
    exit 1
  fi
  drift="$(python3 - "$NEXT" "$src" "$LIVE" <<'PY'
import subprocess, sys
repo, src, live = sys.argv[1:4]
def blobs(cmd, name_at, blob_at):
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    rows = {}
    for line in out.splitlines():
        meta, path = line.split("\t", 1)
        rows[path.lower()] = meta.split()[blob_at]
    return rows
want = blobs(["git", "-C", repo, "ls-tree", "-r", src], 1, 2)
have = blobs(["git", "-C", live, "ls-files", "-s"], 1, 1)
bad = sorted(p for p, b in have.items() if want.get(p) != b)
print(len(bad)); [print(p) for p in bad[:5]]
PY
)" || { echo 'factory-lane-origin: cannot compare live with its source commit' >&2; exit 2; }
  n="$(printf '%s\n' "$drift" | head -1)"
  if [ "$n" != "0" ]; then
    echo "factory-lane-origin: FAIL — $n file(s) in live differ from its source commit ${src:0:12} (changed only in live, or deployed from a dirty tree):" >&2
    printf '%s\n' "$drift" | tail -n +2 | sed 's/^/  /' >&2
    exit 1
  fi
elif ! git -C "$NEXT" merge-base --is-ancestor "$(git -C "$LIVE" rev-parse HEAD)" HEAD; then
  echo 'factory-lane-origin: FAIL — live has commits not yet reachable from next; merge them into next and dev before testing or promoting' >&2
  exit 1
fi
if ! git -C "$DEV" merge-base --is-ancestor "$(git -C "$NEXT" rev-parse HEAD)" HEAD; then
  echo 'factory-lane-origin: FAIL — next has commits not yet reachable from dev; merge them back into dev before testing or promoting' >&2
  exit 1
fi
if [ "$next_git" != "$live_git" ]; then
  echo "factory-lane-origin: PASS (live = ${src:0:12}, reachable from next; next HEAD in dev)"
else
  echo 'factory-lane-origin: PASS (live HEAD in next; next HEAD in dev)'
fi
