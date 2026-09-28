#!/usr/bin/env bash
# Keep the complete promotion chain: live HEAD in next, next HEAD in dev.
set -euo pipefail
FACTORY="${1:?usage: factory-lane-origin.sh FACTORY_PATH}"
FACTORY="$(cd "$FACTORY" && pwd -P)"
CONFIG="$FACTORY/factory.json"
command -v jq >/dev/null || { echo 'factory-lane-origin: jq required' >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "factory-lane-origin: missing $CONFIG" >&2; exit 2; }
paths=()
for lane in dev next live; do
  p="$(jq -er --arg lane "$lane" '.lanes[$lane] | select(type == "string" and length > 0)' "$CONFIG")" || {
    echo "factory-lane-origin: missing $lane lane" >&2; exit 2;
  }
  # JSON contains a literal ~/ prefix; the shell must not expand it here.
  # shellcheck disable=SC2088
  case "$p" in '~/'*) p="$HOME/${p#\~/}" ;; /*) ;; *) p="$FACTORY/$p" ;; esac
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
[ "$dev_git" = "$next_git" ] && [ "$next_git" = "$live_git" ] || { echo 'factory-lane-origin: lanes are different repositories' >&2; exit 1; }
if ! git -C "$NEXT" merge-base --is-ancestor "$(git -C "$LIVE" rev-parse HEAD)" HEAD; then
  echo 'factory-lane-origin: FAIL — live has commits not yet reachable from next; merge them into next and dev before testing or promoting' >&2
  exit 1
fi
if ! git -C "$DEV" merge-base --is-ancestor "$(git -C "$NEXT" rev-parse HEAD)" HEAD; then
  echo 'factory-lane-origin: FAIL — next has commits not yet reachable from dev; merge them back into dev before testing or promoting' >&2
  exit 1
fi
echo 'factory-lane-origin: PASS (live HEAD in next; next HEAD in dev)'
