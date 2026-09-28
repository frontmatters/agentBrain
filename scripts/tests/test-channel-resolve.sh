#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-channel-resolve.sh — the prerelease channel must never serve older code
# than stable.
#
# Regression: 1.10.8, 1.10.9 and 1.10.10 shipped straight to stable, so the
# newest prerelease tag stayed at v1.10.7-prerelease-01 and anyone following
# the prerelease channel silently ran three releases behind. Nothing errored;
# the channel simply pointed backwards. That recurs after every stable cut
# without a prerelease before it, so it is the resolver's job, not a tagging
# convention to remember.
#
# The comparison is deliberate rather than `sort -V`: semver puts a prerelease
# BEFORE its own release (1.10.11-prerelease-01 < 1.10.11) and `sort -V` does
# not, so a naive max would serve the prerelease when the release exists.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-channel-resolve.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

repo="$TMP/repo"
git init -q "$repo"
# channel.sh reads its mode from <brain>/vault/update/config.json; without it the
# script falls back to branch mode and resolve returns a branch, not a tag.
mkdir -p "$repo/vault/update"
cat > "$repo/vault/update/config.json" <<'JSON'
{ "channel": "prerelease", "mode": "tag", "source": "origin",
  "branches": { "edge": "main", "prerelease": "next", "stable": "stable" } }
JSON
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

# resolve <tag>... -> what the prerelease channel serves with those tags present
resolve() {
	git -C "$repo" tag -l | xargs -r git -C "$repo" tag -d >/dev/null 2>&1
	local t; for t in "$@"; do git -C "$repo" tag "$t"; done
	AGENTBRAIN_DIR="$repo" AGENTBRAIN_DEV_DIR="$repo" \
		bash "$ROOT_DIR/scripts/channel.sh" resolve prerelease | tr -d '[:space:]'
}

expect() { # expect <want> <desc> <tag>...
	local want="$1" desc="$2"; shift 2
	local got; got="$(resolve "$@")"
	if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc (want $want, got '${got:-empty}')"; fi
}

# 1. The regression itself: stable moved on, the prerelease tag did not.
expect v1.10.10 "a prerelease older than stable yields stable" \
	v1.10.7-prerelease-01 v1.10.8 v1.10.9 v1.10.10

# 2. A prerelease for a HIGHER version is genuinely the leading edge.
expect v1.10.11-prerelease-01 "a prerelease above stable wins" \
	v1.10.10 v1.10.11-prerelease-01

# 3. Semver tie: a prerelease loses to its own release.
expect v1.10.11 "a prerelease loses to its own release" \
	v1.10.11-prerelease-01 v1.10.11

# 4. No prerelease tags at all: fall back to stable rather than nothing.
expect v1.10.10 "no prerelease tag falls back to stable" v1.10.9 v1.10.10

printf 'channel-resolve: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
