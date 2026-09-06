#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# factory.sh — read a checkout path from factory.json.
#
# One implementation, sourced by everything that needs a path. The previous
# approach derived paths from a "-dev" / "-next" suffix, which is correct only
# while the checkouts sit side by side: strip "-dev" from "framework/dev" and
# nothing changes, so "live" silently becomes the dev checkout.
#
# factory.json is machine-local and gitignored (like brain.json), so ABSENCE IS
# NORMAL — a fresh install has none. Every caller keeps its own default, and
# this only overrides it when the file actually answers. That ordering matters:
# env var > factory.json > the caller's historical default.
#
# Usage:  source "$ROOT/scripts/lib/factory.sh"
#         DIR="${DIR:-$(factory_path releases.root)}"
#         DIR="${DIR:-$HOME/Developer/agentBrain-releases}"   # fallback

# factory_root — the checkout holding factory.json, or empty.
factory_root() {
	local d="${FACTORY_ROOT:-}"
	[ -n "$d" ] && { printf '%s' "$d"; return 0; }
	# Walk up from this library: works whether the caller sits in scripts/ or
	# scripts/release/, and does not care what the checkout is named.
	d="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
	# The file lives in the factory, the directory that holds this checkout
	# (since 2026-09-05); a checkout-local copy still wins when present.
	# Both branches print the path explicitly. A bare `cd -P … && pwd -P` as
	# the last command of a sourced function printed nothing on this shell,
	# and every caller then fell back to its historical default in silence.
	if [ -f "$d/factory.json" ]; then printf '%s' "$d"
	elif [ -f "$d/../factory.json" ]; then printf '%s' "$(cd -P "$d/.." && pwd -P)"
	fi
}

# factory_path <dotted.key> — the expanded path, or empty when unavailable.
# Empty is not an error: it means "no opinion", and the caller falls back.
factory_path() {
	local root; root="$(factory_root)"
	[ -n "$root" ] || return 0
	command -v python3 >/dev/null 2>&1 || return 0
	python3 - "$root/factory.json" "$1" 2>/dev/null <<'PY'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)          # a broken file must not break a release script
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d:
        sys.exit(0)
    d = d[k]
print(os.path.expanduser(d) if isinstance(d, str) else "")
PY
}
