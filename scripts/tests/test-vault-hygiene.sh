#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-vault-hygiene.sh — foreign material is named, not silently tolerated.
#
# The failure this guards against is not a crash. It is a third-party checkout
# sitting in the vault for weeks while every knowledge check quietly treats it
# as your notes. Measured once: 3520 foreign files, 2521 schema failures, and
# 19 dead wiki-links that became 4926 the moment those files left the index,
# because their common basenames had been masking real breakage.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECK="$ROOT/scripts/checks/check-vault-hygiene.sh"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
# A fixture brain has the layout setup makes: vault/ is the directory, local/ the alias.
mkdir -p "$TMP/vault" && ln -sfn vault "$TMP/local"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/vault/research" "$TMP/vault/spaces/sp-test"

# A space is a nested repository on purpose. It must never be reported.
git -C "$TMP/vault/spaces/sp-test" init -q .
printf -- '---\ntype: space\nslug: sp-test\n---\n' > "$TMP/vault/spaces/sp-test/index.md"
out="$(BRAIN_DIR="$TMP" bash "$CHECK" 2>&1)"
case "$out" in
	*"sp-test"*) bad "space-kept" "a space was reported as foreign" ;;
	*) ok "space-kept" "a space with a passport is not foreign" ;;
esac

# A checkout without a passport is somebody else's code.
git -C "$TMP/vault/research" init -q . 2>/dev/null || mkdir -p "$TMP/vault/research/.git"
out="$(BRAIN_DIR="$TMP" bash "$CHECK" 2>&1)"
case "$out" in
	*"research"*) ok "foreign-named" "a checkout with no passport is named" ;;
	*) bad "foreign-named" "a foreign checkout went unreported" ;;
esac
case "$out" in
	*workspace/external*) ok "points-somewhere" "the warning says where it belongs" ;;
	*) bad "points-somewhere" "the warning does not name the workspace" ;;
esac

# It warns; it never gates. A clone mid-review is a normal state, and a check
# that blocks work is a check people learn to skip.
BRAIN_DIR="$TMP" bash "$CHECK" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "never-gates" "exits 0 even with a foreign checkout present" \
	|| bad "never-gates" "the check failed the build"

# Setup must create the workspace, so there is somewhere to put such a thing
# before someone puts it in the vault.
grep -q 'ensure_workspace' "$ROOT/scripts/setup/setup-local-vault.sh" \
	&& ok "setup-creates" "setup creates the workspace beside the vault" \
	|| bad "setup-creates" "nothing creates the workspace"
[ -f "$ROOT/templates/workspace-readme.md" ] \
	&& ok "readme-ships" "the workspace README ships as a template" \
	|| bad "readme-ships" "no workspace README to install"

# A new space must be versioned on creation. Versioning is local and free;
# backup needs a remote, and splitting the two left a space created with
# sync:none unversioned until somebody remembered to seal it. A 594-line
# assessment then sat in exactly one place with no history behind it.
grep -q 'SPACES_ROOT/.gitignore' "$ROOT/scripts/new-space.sh" \
	&& ok "fail-closed" "new-space writes the fail-closed spaces/.gitignore" \
	|| bad "fail-closed" "nothing writes the second layer"

[ "$fail" -ne 0 ] && { echo "FAIL test-vault-hygiene" >&2; exit 1; }
echo "PASS test-vault-hygiene"
