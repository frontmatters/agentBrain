#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-factory-paths.sh — the checkout paths come from factory.json, and the
# suffix convention is only a fallback.
#
# Why this exists: brain.sh used to derive every path from a "-dev" / "-next"
# suffix. That silently produces the WRONG answer for a nested layout — strip
# "-dev" from "framework/dev" and nothing changes, so live becomes dev. The
# factory plan moves the checkouts, so this had to be settled before anything
# was moved. The test guards both halves: the file wins where it exists, and
# the convention still carries a checkout that has no file.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A nested layout: exactly the shape the suffix convention cannot read.
mkdir -p "$TMP/framework/dev/scripts" "$TMP/framework/live" "$TMP/framework/next"
cp "$ROOT/scripts/brain.sh" "$TMP/framework/dev/scripts/brain.sh"
cat > "$TMP/framework/dev/factory.json" <<JSON
{ "version": "1.1", "framework": {
  "dev": "$TMP/framework/dev", "next": "$TMP/framework/next",
  "live": "$TMP/framework/live" } }
JSON

read_live() { # read_live <checkout-dir> — BRAIN_LIVE as brain.sh resolves it
	HERE="$1" bash -c '
		HERE="$HERE"
		factory_path() {
			[ -f "$HERE/factory.json" ] || return 0
			python3 - "$HERE/factory.json" "$1" 2>/dev/null <<PY
import json, os, sys
try: d = json.load(open(sys.argv[1]))
except (OSError, ValueError): sys.exit(0)
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d: sys.exit(0)
    d = d[k]
print(os.path.expanduser(d) if isinstance(d, str) else "")
PY
		}
		BASE="${HERE%-dev}"; BASE="${BASE%-next}"
		L="$(factory_path framework.live)"
		echo "${L:-$BASE}"'
}

live="$(read_live "$TMP/framework/dev")"
[ "$live" = "$TMP/framework/live" ] \
	&& ok "nested" "factory.json resolves live correctly under a nested layout" \
	|| bad "nested" "expected $TMP/framework/live, got $live"

# Without the file, the convention must still carry a side-by-side checkout.
mkdir -p "$TMP/agentBrain-dev"
live2="$(read_live "$TMP/agentBrain-dev")"
[ "$live2" = "$TMP/agentBrain" ] \
	&& ok "fallback" "the suffix convention still works with no factory.json" \
	|| bad "fallback" "expected $TMP/agentBrain, got $live2"

# The convention alone, on the nested layout, must be WRONG — that is the bug
# this file exists for. If this ever passes, the fallback has silently changed.
nested_conv="$(cd "$TMP/framework/dev" && bash -c 'H="$PWD"; B="${H%-dev}"; echo "${B%-next}"')"
[ "$nested_conv" = "$TMP/framework/dev" ] \
	&& ok "bug-still-real" "the suffix convention alone still misreads a nested path" \
	|| bad "bug-still-real" "the convention no longer misreads; this test's premise moved"

# The shipped factory.json must describe paths that exist.
if [ -f "$ROOT/factory.json" ]; then
	missing="$(python3 - "$ROOT/factory.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); out = []
def walk(o, p=""):
    for k, v in o.items():
        if k.startswith(("$", "//")): continue
        if isinstance(v, dict): walk(v, f"{p}.{k}")
        elif isinstance(v, str) and v.startswith("~") and not os.path.exists(os.path.expanduser(v)):
            out.append(f"{p}.{k}={v}")
walk(d)
print(" ".join(out))
PY
)"
	[ -z "$missing" ] && ok "paths-exist" "every path in factory.json exists" \
		|| bad "paths-exist" "missing: $missing"
else
	# Absent is valid: factory.json is machine-local (gitignored, like
	# brain.json), so a fresh clone has none and the fallback carries it.
	ok "paths-exist" "no factory.json on this checkout — fallback path, skipped"
fi

# Every consumer must read through the shared library, not its own copy: five
# private implementations is how one of them silently drifts.
copies=0
for f in scripts/brain.sh scripts/release/deploy-dev-to-live.sh \
         scripts/release/release.sh scripts/release/release-check.sh \
         scripts/release/publish-addon.sh; do
	[ -f "$ROOT/$f" ] || continue
	if grep -q "^factory_path() {" "$ROOT/$f"; then
		bad "one-impl" "$f defines its own factory_path instead of sourcing the library"
		copies=$((copies + 1))
	elif ! grep -q "lib/factory.sh" "$ROOT/$f"; then
		bad "sources-lib" "$f neither sources lib/factory.sh nor defines the function"
	fi
done
[ "$copies" -eq 0 ] && ok "one-impl" "factory_path is defined in exactly one place"

# Absence must not change behaviour for a checkout that never had the file.
if [ -f "$ROOT/factory.json" ]; then
	mv "$ROOT/factory.json" "$TMP/factory.json.away"
	out="$(cd "$ROOT" && bash -c 'source scripts/lib/factory.sh; factory_path framework.live')"
	mv "$TMP/factory.json.away" "$ROOT/factory.json"
	[ -z "$out" ] && ok "absent" "factory_path returns empty with no file, so callers fall back" \
		|| bad "absent" "expected empty, got '$out'"
fi

[ "$fail" -ne 0 ] && { echo "FAIL test-factory-paths" >&2; exit 1; }
echo "PASS test-factory-paths"
