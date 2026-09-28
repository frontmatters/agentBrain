#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# negative/check-addon-distribution.sh — the gate fires on each trap, and is
# silent on each fix. A guard nobody has watched fail is a guard nobody knows.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
GUARD="$ROOT/scripts/checks/check-addon-distribution.sh"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

# A throwaway repository, because the guard reads git state (ls-files,
# check-ignore) and must never be pointed at the real checkout. Same trap the
# repo-snapshot guard exists for: `git -C ""` is the cwd.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -n "$TMP" ] || exit 1
mkdir -p "$TMP/scripts/checks" "$TMP/scripts/lib" "$TMP/system/addons"
cp "$GUARD" "$TMP/scripts/checks/"
printf '# check\tpattern\texpires\treason\n' > "$TMP/scripts/lib/exemptions.tsv"
cd "$TMP" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed

mk() { # <addon> <author> [license]
	mkdir -p "system/addons/$1"
	{ echo '---'; echo "id: $1"; echo "author: $2"; [ -n "${3:-}" ] && echo "license: $3"; echo '---'; } \
		> "system/addons/$1/manifest.md"
}
run() { bash scripts/checks/check-addon-distribution.sh >/dev/null 2>&1; }

# ── licence arm ─────────────────────────────────────────────────────────────
mk own frontmatters
run && ok "own" "the maintainer's own addon needs no licence" || bad "own" "flagged an addon the maintainer wrote"

mk third somebody-else
run && bad "third" "a third-party addon with no licence went through" || ok "third" "a third-party addon with no licence is named"

mk third somebody-else MIT
run && ok "licensed" "a licence in the manifest satisfies it" || bad "licensed" "rejected an addon that names its licence"

# NONE is a real answer, not a missing one: upstream publishes no licence file.
mk third somebody-else NONE
run && ok "none" "NONE counts as an answer" || bad "none" "treated NONE as missing"

# ── exemption arm ───────────────────────────────────────────────────────────
mk third somebody-else
printf 'check-addon-license\tthird\t2026-12-24\tdated, with a reason\n' >> scripts/lib/exemptions.tsv
run && ok "exempt" "a registered exemption is honoured" || bad "exempt" "ignored the exemption register"

# Whole-field match, or one name exempts its neighbours.
mk third-extra somebody-else
run && bad "prefix" "an exemption for 'third' also exempted 'third-extra'" || ok "prefix" "the exemption matches the whole name, not a prefix"
rm -rf system/addons/third-extra

# ── private-directory arm ───────────────────────────────────────────────────
mkdir -p system/addons-private/secret
printf 'x\n' > system/addons-private/secret/plugin.sh
run && bad "unignored" "a private directory with no gitignore rule passed" || ok "unignored" "an unignored private directory is named"

printf '/system/addons-private/\n' > .gitignore
run && ok "ignored" "a properly ignored private directory is fine" || bad "ignored" "rejected a correctly ignored private directory"

# Ignored but tracked is the dangerous middle state: release.sh builds from
# git ls-files, so a tracked file ships whatever .gitignore says.
git add -f system/addons-private/secret/plugin.sh 2>/dev/null
run && bad "tracked" "a tracked file under the private directory would ship" || ok "tracked" "a tracked private file is named"

if [ "$fail" -eq 0 ]; then echo "PASS negative/check-addon-distribution"; else echo "FAIL negative/check-addon-distribution" >&2; exit 1; fi
