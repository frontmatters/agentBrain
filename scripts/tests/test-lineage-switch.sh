#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-lineage-switch.sh: a checkout can switch between the LAN and the online
# source and still name its release.
#
# The two lineages share tag names on different commits. A plain tag fetch
# refuses a same-named tag in silence and describe yields a bare hash. This
# builds two unrelated sources with the same tag and switches a checkout
# between them, both ways.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
# shellcheck source=scripts/lib/lineage.sh
. "$ROOT/scripts/lib/lineage.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export GIT_CEILING_DIRECTORIES="$T"
mk() { # <dir> <marker>: an unrelated lineage with tag v9.9.9 on its own commit
	git init -q -b main "$1" && (cd "$1" && git config user.email t@t && git config user.name t \
		&& echo "$2" > README && git add README && git commit -qm "$2" && git tag v9.9.9)
}
mk "$T/lan" lan; mk "$T/public" public
git clone -q "$T/lan" "$T/co" 2>/dev/null
[ "$(lineage_identity "$T/co")" = "v9.9.9" ] && ok "start" "a clone of the LAN source reports v9.9.9" || bad "start" "got '$(lineage_identity "$T/co")'"

# The failure this guards against: a plain fetch keeps the old tag, describe goes bare.
git -C "$T/co" fetch -q --tags "$T/public" main 2>/dev/null; git -C "$T/co" reset -q --hard FETCH_HEAD
case "$(lineage_identity "$T/co")" in
	v9.9.9) bad "plain-fetch" "a plain tag fetch moved the tag; the bug this test guards is gone or not reproduced" ;;
	*) ok "plain-fetch" "a plain tag fetch leaves the old tag; describe is bare ('$(git -C "$T/co" describe --tags --always)')" ;;
esac

adopt_lineage "$T/co" "$T/public" main; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$T/co" rev-parse v9.9.9)" = "$(git -C "$T/public" rev-parse v9.9.9)" ] \
	&& ok "to-public" "adopting the public source moves the tag and anchors describe ($(lineage_identity "$T/co"))" \
	|| bad "to-public" "rc=$rc identity='$(lineage_identity "$T/co")'"
adopt_lineage "$T/co" "$T/lan" main; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$T/co" rev-parse v9.9.9)" = "$(git -C "$T/lan" rev-parse v9.9.9)" ] \
	&& ok "to-lan" "and back to the LAN source ($(lineage_identity "$T/co"))" \
	|| bad "to-lan" "rc=$rc identity='$(lineage_identity "$T/co")'"

# The LAN installer hands over a git BUNDLE (serve-lan.sh builds it with --tags).
# From a checkout that follows the public source, adopting the bundle must land
# on the LAN tag; and the public source must win again afterwards.
git -C "$T/lan" bundle create "$T/lan.bundle" --tags main HEAD >/dev/null 2>&1
adopt_lineage "$T/co" "$T/public" main >/dev/null 2>&1
adopt_lineage "$T/co" "$T/lan.bundle" main; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$T/co" rev-parse v9.9.9)" = "$(git -C "$T/lan" rev-parse v9.9.9)" ] \
	&& ok "online-to-lan-bundle" "a LAN bundle adopted over a public checkout anchors on the LAN tag ($(lineage_identity "$T/co"))" \
	|| bad "online-to-lan-bundle" "rc=$rc identity='$(lineage_identity "$T/co")'"
adopt_lineage "$T/co" "$T/public" main; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$T/co" rev-parse v9.9.9)" = "$(git -C "$T/public" rev-parse v9.9.9)" ] \
	&& ok "lan-bundle-to-online" "and the public source wins again over the bundle's tags ($(lineage_identity "$T/co"))" \
	|| bad "lan-bundle-to-online" "rc=$rc identity='$(lineage_identity "$T/co")'"

# The piped installer carries an inlined copy of the two functions: keep it identical.
lib="$(sed -n '/^lineage_identity() {/,/^}/p;/^adopt_lineage() {/,/^}/p' "$ROOT/scripts/lib/lineage.sh")"
inl="$(sed -n '/^lineage_identity() {/,/^}/p;/^adopt_lineage() {/,/^}/p' "$ROOT/scripts/installer/install.sh")"
[ "$lib" = "$inl" ] && ok "inlined" "install.sh carries the same adopt_lineage as scripts/lib/lineage.sh" \
	|| bad "inlined" "install.sh's inlined lineage functions differ from scripts/lib/lineage.sh"
grep -q 'fetch --quiet --force --prune-tags --tags "$remote"' "$ROOT/scripts/brain-update.sh" \
	&& ok "brain-update" "brain-update lets the remote win on tags" \
	|| bad "brain-update" "brain-update still fetches tags without --force"

[ "$fail" -ne 0 ] && { echo "FAIL test-lineage-switch" >&2; exit 1; }
echo "PASS test-lineage-switch"
