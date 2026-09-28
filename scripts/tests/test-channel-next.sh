#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Public next is a distinct, RC-only channel. No legacy prerelease or stable fallback.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
repo="$T/repo"
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$repo/vault/update"
printf '{"channel":"next","mode":"tag","source":"origin","branches":{"next":"next","stable":"main"}}\n' > "$repo/vault/update/config.json"
pass=0; fail=0
expect() { # channel expected message tags...
  local chan="$1" want="$2" msg="$3" got t; shift 3
  git -C "$repo" tag -l | while IFS= read -r t; do [ -z "$t" ] || git -C "$repo" tag -d "$t" >/dev/null; done
  for t in "$@"; do git -C "$repo" tag "$t"; done
  got="$(AGENTBRAIN_DIR="$repo" AGENTBRAIN_DEV_DIR="$repo" bash "$ROOT_DIR/scripts/channel.sh" resolve "$chan")"
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf '  ok: %s\n' "$msg"; else fail=$((fail+1)); printf '  FAIL: %s (expected %s, got %s)\n' "$msg" "${want:-empty}" "${got:-empty}" >&2; fi
}
expect next '' 'no RC means no public next' v1.13.1 v1.14.0-prerelease-03
expect next v1.14.0-rc.1 'RC beats lower stable and legacy prerelease' v1.13.1 v1.14.0-prerelease-03 v1.14.0-rc.1
expect next v1.14.0-rc.10 'numeric RC order' v1.13.1 v1.14.0-rc.9 v1.14.0-rc.10
expect next '' 'final stable makes its RC ineligible' v1.14.0 v1.14.0-rc.10
expect next '' 'older RC cannot downgrade newer stable' v1.15.0 v1.14.0-rc.10
expect next '' 'malformed RC never selected' v1.13.1 v1.14.0-rc.0 v1.14.0-rc.bad
expect stable v1.13.1 'stable ignores RC' v1.13.1 v1.14.0-rc.1
python3 - "$repo/vault/update/config.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d['mode'] = 'branch'
with open(p, 'w') as f: json.dump(d, f)
PY
expect next v1.14.0-rc.1 'branch mode cannot expose mutable next branch' v1.13.1 v1.14.0-rc.1
printf 'channel-next: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
