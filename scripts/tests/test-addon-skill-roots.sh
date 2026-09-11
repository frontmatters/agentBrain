#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-addon-skill-roots.sh — an addon's SKILL.md is linked from every root that
# counts as an addon source.
#
# The regression: addon skills were linked from system/addons only, while
# addon-package.sh had always accepted "system/addons:vault/addons". A private
# addon in the vault could therefore ship a SKILL.md that no agent ever saw, and
# the only way to make a skill reachable was to promote the addon to the public
# layer, whether or not it belonged there.
#
# Two latent bugs sat in the same function. The symlink target was hard-coded to
# system/addons regardless of the root passed in, so any other root produced a
# dangling link; and the prune loop removed links whose addon was absent from
# the single root it was given, which is why the fix could not be "call it twice".
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-addon-roots.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=../lib/skills.sh
. "$ROOT_DIR/scripts/lib/skills.sh"

BRAIN="$TMP/brain"
SYS="$BRAIN/system/addons"
VLT="$BRAIN/vault/addons"
DEST="$TMP/agent/skills"
mkdir -p "$SYS/pub" "$VLT/priv" "$VLT/off" "$DEST"

for a in "$SYS/pub" "$VLT/priv" "$VLT/off"; do
	printf -- '---\nname: %s\n---\n' "$(basename "$a")" > "$a/SKILL.md"
done
# Enabled state lives in the vault for both layers; "off" is deliberately absent.
mkdir -p "$VLT/pub" "$VLT/priv"
: > "$VLT/pub/enabled"
: > "$VLT/priv/enabled"

sync() { skilllib_sync_addon_skills "$DEST" "$SYS:$VLT" "$VLT" "$BRAIN"; }
sync

# --- 1. the public layer still works -----------------------------------------
[ -L "$DEST/pub/SKILL.md" ] && t_ok "a system addon is linked" || t_bad "system addon not linked"

# --- 2. the private layer works too, which is the whole point ----------------
[ -L "$DEST/priv/SKILL.md" ] \
	&& t_ok "a vault addon is linked" \
	|| t_bad "a vault addon was not linked"

# --- 3. each link points at the root it was found in --------------------------
# Hard-coding system/addons made this dangle for anything else.
case "$(readlink "$DEST/priv/SKILL.md")" in
	*"/vault/addons/priv/SKILL.md") t_ok "the link points into the root it came from" ;;
	*) t_bad "link points elsewhere: $(readlink "$DEST/priv/SKILL.md")" ;;
esac
[ -e "$DEST/priv/SKILL.md" ] && t_ok "the link resolves" || t_bad "the link dangles"

# --- 4. a disabled addon is never linked -------------------------------------
[ ! -e "$DEST/off/SKILL.md" ] \
	&& t_ok "a disabled addon stays unlinked" \
	|| t_bad "linked an addon that is not enabled"

# --- 5. syncing twice is stable ----------------------------------------------
# The prune loop used to delete anything missing from its single root, so a
# second pass over another root wiped the first pass.
sync
[ -L "$DEST/pub/SKILL.md" ] && [ -L "$DEST/priv/SKILL.md" ] \
	&& t_ok "a second sync keeps both layers" \
	|| t_bad "a second sync removed a link"

# --- 6. disabling prunes, in either layer ------------------------------------
rm -f "$VLT/priv/enabled"
sync
[ ! -e "$DEST/priv/SKILL.md" ] \
	&& t_ok "disabling a vault addon prunes its link" \
	|| t_bad "a disabled vault addon kept its link"
[ -L "$DEST/pub/SKILL.md" ] && t_ok "pruning one layer leaves the other alone" || t_bad "pruning removed the system link"

# --- 7. a skill the user wrote themselves is never touched -------------------
mkdir -p "$DEST/mine"
printf 'not a link\n' > "$DEST/mine/SKILL.md"
sync
[ -f "$DEST/mine/SKILL.md" ] && [ ! -L "$DEST/mine/SKILL.md" ] \
	&& t_ok "a user's own skill is left alone" \
	|| t_bad "clobbered a skill the user wrote"

if [ "$((pass + fail))" -lt 9 ]; then
	printf 'addon-skill-roots: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'addon-skill-roots: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
