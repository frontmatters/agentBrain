#!/usr/bin/env bash
# test-factory-release.sh — a release is cut only when live is next and sits on
# the vVERSION tag (the factory rule "release only what live is, on its tag").
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1" >&2; }
F="$T/tool.factory"; mkdir -p "$F/releases" "$F/R&D"/{dashboards,decisions,captures,renders,logs,experiments}
echo "# tool" > "$F/README.md"
g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }
mkdir -p "$F/tool-dev" && g -C "$F/tool-dev" init -q -b tool-dev && echo 1.0.0 > "$F/tool-dev/VERSION" && g -C "$F/tool-dev" add -A && g -C "$F/tool-dev" commit -q -m one
g -C "$F/tool-dev" branch tool-next && g -C "$F/tool-dev" branch tool-live
g -C "$F/tool-dev" worktree add -q "$F/tool-next" tool-next && g -C "$F/tool-dev" worktree add -q "$F/tool" tool-live
printf '{"project":"tool","lanes":{"dev":"%s/tool-dev","next":"%s/tool-next","live":"%s/tool"},"releases":"%s/releases","commands":{"test":"true"}}\n' "$F" "$F" "$F" "$F" > "$F/factory.json"
rel() { (cd "$F" && FACTORY_PATH="$F" bash "$HERE/factory-release.sh" >"$T/out" 2>&1); }

rel; rc=$?
[ "$rc" = 3 ] && grep -q "not on tag v1.0.0" "$T/out" && [ ! -e "$F/releases/tool-v1.0.0.tar.gz" ] && ok "no tag on live: refused, nothing built" || bad "untagged: rc=$rc $(tail -2 "$T/out")"
g -C "$F/tool-dev" tag v1.0.0
printf 'private.txt\n' > "$T/ignore"
g -C "$F/tool-next" config core.excludesFile "$T/ignore"
printf 'untracked\n' > "$F/tool-next/private.txt"
rel; rc=$?
[ "$rc" = 0 ] && [ -f "$F/releases/tool-v1.0.0.tar.gz" ] && ok "live is next and on v1.0.0: released" || bad "tagged: rc=$rc $(tail -3 "$T/out")"
if [ "$rc" = 0 ] && ! tar -tzf "$F/releases/tool-v1.0.0.tar.gz" | grep -q 'private.txt'; then
  ok "untracked lane file excluded from archive"
else bad "untracked lane file reached archive"; fi
echo 1.1.0 > "$F/tool-dev/VERSION" && g -C "$F/tool-dev" commit -q -am two && g -C "$F/tool-dev" tag v1.1.0
g -C "$F/tool-next" merge -q --ff-only tool-dev
rel; rc=$?
[ "$rc" = 3 ] && grep -q "is not next" "$T/out" && [ ! -e "$F/releases/tool-v1.1.0.tar.gz" ] && ok "next ahead of live (promote failed or skipped): refused, nothing built" || bad "ahead: rc=$rc $(tail -2 "$T/out")"
echo "test-factory-release: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
