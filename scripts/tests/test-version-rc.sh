#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Read-side VERSION format cannot lag behind factory RC bump/release tools.
set -uo pipefail
ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/scripts/checks"
cp "$ROOT/scripts/checks/check-version.sh" "$T/repo/scripts/checks/"
pass=0; fail=0
check() { local want="$1" version="$2" rc=0; printf '%s\n' "$version" > "$T/repo/VERSION"; bash "$T/repo/scripts/checks/check-version.sh" >/dev/null 2>&1 || rc=$?; if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -ne 0 ]; }; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $version ($want, rc=$rc)" >&2; fi; }
check pass 1.13.1
check pass 1.14.0-prerelease-03
check pass 1.14.0-rc.1
check pass 1.14.0-rc.10
check fail 1.14.0-rc.0
check fail 1.14.0-rc.01
check fail 1.14.0-rc.bad
check fail 1.14.0-rc.1-garbage
printf 'version-rc: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
