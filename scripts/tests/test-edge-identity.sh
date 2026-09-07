#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-edge-identity.sh — an edge install must be able to say which build it is.
#
# There are two kinds of version. VERSION is a DECLARATION: what you intend to
# release next. `git describe` is a MEASUREMENT: what you actually have. A
# declaration can drift from reality; a measurement cannot. Edge has no release
# to declare, so its identity has to be the measurement.
#
# That only works if the tags travel. `git bundle create ... main HEAD` ships no
# tags, and a clone from such a bundle can only report a bare hash: no idea which
# release it is past, or by how far. One word fixes it, and this test keeps that
# word there.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

# 1. The LAN bundle must carry tags.
if grep -q 'bundle create .*--tags' "$ROOT/scripts/installer/serve-lan.sh"; then
	ok "bundle-tags" "serve-lan.sh bundles the tags"
else
	bad "bundle-tags" "serve-lan.sh builds a bundle without --tags; a clone cannot describe itself"
fi

# 1b. The update path of the installer must carry the tags too: the public repo
#     is a rewriting snapshot, so a checkout's old tags never sit on the new
#     lineage. Measured on an updated consumer checkout: describe gave a bare
#     hash and this test failed there while passing on a fresh clone.
#     And with --force: a checkout that once tracked the private lineage holds a
#     v-tag of the same name on another commit, and a plain --tags fetch refuses
#     it in silence ("would clobber existing tag"). Measured on the Air: 28 tags,
#     v1.10.4 on the Gitea commit, describe gave 8042b0c.
if grep -qE 'adopt_lineage "\$DEST" "\$REPO" "\$BRANCH"' "$ROOT/scripts/installer/install.sh" \
	&& grep -qE 'adopt_lineage "\$DEST" "\$tmpb" "\$BRANCH"' "$ROOT/scripts/installer/install.sh"; then
	ok "update-tags" "both installer paths adopt the source's lineage (forced tags, verified describe)"
else
	bad "update-tags" "an installer path updates a checkout without adopt_lineage; a same-named old tag wins and describe yields a bare hash"
fi

# 2. Prove it end to end: a clone of that bundle must resolve a real identity,
#    not a bare hash. Skipped where there are no tags to carry.
# A shallow clone or a checkout without a main branch (an install from a LAN
# bundle, or an updated consumer checkout) cannot build this bundle at all;
# that says nothing about serve-lan.sh, so it is a skip, not a failure.
if [ "$(git -C "$ROOT" tag | wc -l | tr -d ' ')" -gt 0 ] \
	&& [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ] \
	&& git -C "$ROOT" rev-parse --verify -q main >/dev/null 2>&1; then
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	if git -C "$ROOT" bundle create "$TMP/ab.bundle" --tags main HEAD >/dev/null 2>&1 \
		&& git clone -q "$TMP/ab.bundle" "$TMP/clone" 2>/dev/null; then
		n="$(git -C "$TMP/clone" tag | wc -l | tr -d ' ')"
		desc="$(git -C "$TMP/clone" describe --tags --match 'v*' --always 2>/dev/null)"
		[ "$n" -gt 0 ] && ok "clone-tags" "the clone carries $n tag(s)" \
			|| bad "clone-tags" "the clone carries no tags"
		case "$desc" in
			v*) ok "clone-describe" "the clone reports $desc" ;;
			*)  bad "clone-describe" "describe gave '$desc', not an anchored identity" ;;
		esac
	else
		bad "clone-tags" "could not build or clone the bundle"
	fi
else
	ok "clone-tags" "no tags in this checkout — skipped"
fi

# 3. brain status must surface the drift, not only the declaration. Two machines
#    both reporting the same VERSION can be many commits apart; that is the whole
#    point of showing it.
if grep -q 'drift_of' "$ROOT/scripts/brain.sh"; then
	ok "status-drift" "brain.sh reports how far past its tag a checkout sits"
else
	bad "status-drift" "brain.sh shows VERSION only; drift from the tag stays invisible"
fi

# 4. Picking a channel must not rewrite the mode. `set edge` used to flip the
# whole install to branch mode, as a workaround for brain-update refusing edge
# in tag mode. That refusal is gone, and a command that silently rewrites a
# setting the user chose is its own defect.
if grep -A8 'cfg_set channel' "$ROOT/scripts/channel.sh" | grep -q 'cfg_set mode'; then
	bad "no-mode-flip" "channel.sh set still rewrites the mode as a side effect"
else
	ok "no-mode-flip" "picking a channel leaves the mode alone"
fi

# 5. edge must resolve in BOTH modes: it is a branch by nature, and the mode
# governs release channels only.
if grep -q 'chan_is_branch' "$ROOT/scripts/brain-update.sh" \
   && ! grep -q "not valid in tag-mode" "$ROOT/scripts/brain-update.sh"; then
	ok "edge-both-modes" "brain-update resolves edge as a branch in either mode"
else
	bad "edge-both-modes" "brain-update still ties edge's resolution to the mode"
fi

# 6. Edge must not be offered to someone who installed from the public
# snapshot. There, "edge" resolves to the last deploy, which is weeks old under
# a label that promises the opposite. The gate is derived from the checkout's
# own origin, so it cannot drift the way a recorded flag would.
if python3 -c "
import json,sys
d=json.load(open('$ROOT/system/skills/onboard/choices.json'))
o=[x for x in d['fields']['channel']['options'] if x.get('value')=='edge']
sys.exit(0 if o and o[0].get('requires')=='insider' else 1)" 2>/dev/null; then
	ok "edge-gated" "the edge channel declares its insider requirement"
else
	bad "edge-gated" "edge is offered unconditionally in the onboarding choices"
fi

if grep -q '_available' "$ROOT/scripts/onboard-wizard.sh" \
   && grep -q '_is_insider' "$ROOT/scripts/onboard-wizard.sh"; then
	ok "wizard-filters" "the wizard drops options whose requirement does not hold"
else
	bad "wizard-filters" "the wizard shows every option regardless of its requirement"
fi

# The detection itself: a public host is an outsider, anything else an insider.
for probe in "https://github.com/x/y.git|0" "git://lan-host/agentBrain-dev|1" \
             "http://nas:3030/frontmatters/agentBrain-dev.git|1" "|0"; do
	url="${probe%|*}"; want="${probe##*|}"
	got=1
	case "$url" in *github.com*|*gitlab.com*|*codeberg.org*) got=0 ;; "") got=0 ;; esac
	[ "$got" = "$want" ] && ok "detect" "${url:-<no remote>} -> insider=$got" \
		|| bad "detect" "${url:-<no remote>} gave insider=$got, expected $want"
done

# 7. The LAN server must notice when main moves. Building once at startup is
# how it ended up serving a tree 21 commits old with nothing to say so.
if [ -f "$ROOT/scripts/installer/serve-lan-handler.py" ]; then
	ok "handler" "the LAN server has a request handler, not a static file server"
else
	bad "handler" "serve-lan-handler.py is missing; the server cannot notice a moved main"
fi
grep -q -- '--build-only' "$ROOT/scripts/installer/serve-lan.sh" \
	&& ok "build-once" "the build lives in serve-lan.sh and the handler calls it" \
	|| bad "build-once" "serve-lan.sh has no --build-only; the handler would need its own copy"
grep -q 'mv -f "\$tmp_b"' "$ROOT/scripts/installer/serve-lan.sh" \
	&& ok "atomic" "the bundle is renamed into place, never written under a reader" \
	|| bad "atomic" "the bundle is written in place; a client mid-download can read a partial file"
grep -q 'python3 -m http.server' "$ROOT/scripts/installer/serve-lan.sh" \
	&& bad "no-static" "serve-lan.sh still starts a plain static file server" \
	|| ok "no-static" "no plain static server remains"

[ "$fail" -ne 0 ] && { echo "FAIL test-edge-identity" >&2; exit 1; }
echo "PASS test-edge-identity"
