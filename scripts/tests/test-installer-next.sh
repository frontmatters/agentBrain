#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Exercise the real piped-installer preflight and the destructive-reset boundary
# against a local public-remote fixture. No network, tokens or real HOME.
set -uo pipefail
ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
remote="$T/public.git"; work="$T/source"; checkout="$T/installed"
git init -q --bare "$remote"; git init -q -b main "$work"
git -C "$work" -c user.name=test -c user.email=t@t commit -qm stable --allow-empty
git -C "$work" tag v1.13.1
git -C "$work" remote add origin "$remote"
git -C "$work" push -q origin main --tags
# The preflight is inline in install.sh so a curl|bash installation needs no
# helper on disk. Extract precisely that case statement, never mock its checks.
sed -n '/^case "${AB_CHANNEL:-stable}:$BRANCH" in/,/^esac/p' "$ROOT/scripts/installer/install.sh" > "$T/preflight.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }
preflight() { # channel branch [bundle] -> rc + version
  REPO="$remote" BRANCH="$2" AB_CHANNEL="$1" AB_BUNDLE="${3:-}" bash -c 'set -euo pipefail; . "$1"; printf "version=%s\n" "${AB_VERSION:-stable}"' _ "$T/preflight.sh" 2>/dev/null
}
[ "$(preflight stable main)" = version=stable ] && ok 'default stable main remains available' || bad 'stable main refused'
preflight stable next >/dev/null && bad 'moving next branch allowed without opt-in' || ok 'next requires explicit opt-in'
preflight next main >/dev/null && bad 'next on main silently installed stable' || ok 'next cannot use main'
preflight next next >/dev/null && bad 'next existed with no reviewed RC' || ok 'next without branch/tag is refused'
git -C "$work" checkout -qb next
git -C "$work" -c user.name=test -c user.email=t@t commit -qm unreviewed --allow-empty
git -C "$work" tag v1.14.0-prerelease-03
git -C "$work" push -q origin next --tags
preflight next next >/dev/null && bad 'legacy prerelease unlocked public next' || ok 'legacy prerelease never unlocks next'
git clone -q "$remote" "$checkout" 2>/dev/null || git clone -q -b main "$remote" "$checkout"
git -C "$checkout" checkout -q main 2>/dev/null || true
before="$(git -C "$checkout" rev-parse HEAD)"
AB_CHANNEL=next AB_VERSION=1.14.0-rc.1 bash -c '. "$1"; adopt_lineage "$2" "$3" next' _ "$ROOT/scripts/lib/lineage.sh" "$checkout" "$remote" >/dev/null 2>&1 && bad 'untagged next reset existing checkout' || ok 'untagged next does not reset existing checkout'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$before" ] || bad 'existing checkout changed despite failed next gate'
git -C "$work" tag v1.14.0-rc.1
git -C "$work" push -q origin v1.14.0-rc.1
[ "$(preflight next next)" = version=1.14.0-rc.1 ] && ok 'matching RC tag on next is accepted' || bad 'matching RC refused'
preflight next next http://lan/bundle >/dev/null && bad 'LAN bundle bypassed public next' || ok 'LAN bundles refused on public next'
AB_CHANNEL=next AB_VERSION=1.14.0-rc.2 bash -c '. "$1"; adopt_lineage "$2" "$3" next' _ "$ROOT/scripts/lib/lineage.sh" "$checkout" "$remote" >/dev/null 2>&1 && bad 'stale version reset existing checkout' || ok 'stale version cannot reset'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$before" ] || bad 'checkout changed after stale version'
AB_CHANNEL=next AB_VERSION=1.14.0-rc.1 bash -c '. "$1"; adopt_lineage "$2" "$3" next' _ "$ROOT/scripts/lib/lineage.sh" "$checkout" "$remote" >/dev/null 2>&1 && ok 'matching pinned RC resets existing clean checkout' || bad 'matching pinned RC refused'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$(git -C "$work" rev-parse HEAD)" ] || bad 'checkout did not reach RC commit'
# A dirty machine cannot lose work to an opt-in installer.
printf 'my notes\n' > "$checkout/notes.txt"
AB_CHANNEL=next AB_VERSION=1.14.0-rc.1 bash -c '. "$1"; adopt_lineage "$2" "$3" next' _ "$ROOT/scripts/lib/lineage.sh" "$checkout" "$remote" >/dev/null 2>&1 && bad 'dirty next checkout reset' || ok 'dirty next checkout refused'
[ -f "$checkout/notes.txt" ] || bad 'dirty checkout lost its notes'
git -C "$work" checkout -qb stable-final next
printf '1.14.0\n' > "$work/VERSION"
git -C "$work" add VERSION; git -C "$work" -c user.name=test -c user.email=t@t commit -qm stable-final
git -C "$work" tag v1.14.0
git -C "$work" push -q origin stable-final:main v1.14.0
preflight next next >/dev/null && bad 'older RC still installed after stable final' || ok 'Next refuses RC after its stable release'
printf 'installer-next: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
