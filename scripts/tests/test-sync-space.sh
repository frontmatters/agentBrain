#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-sync-space.sh — proves scripts/sync/sync-space.sh backs a space up to ITS OWN
# non-personal remote, never the personal vault, and only when sync: is a remote.
#
#   Case A (sync: none): versioned and committed locally, no remote, exit 0;
#                        the personal vault's
#                        `git status` shows nothing under spaces/.
#   Case B (real remote): pushes the space — and ONLY the space — to a throwaway
#                        file:// bare repo; the personal vault stays untouched.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT_DIR/scripts/lib/vault.sh"
LOCAL_DIR="$VAULT_DIR"
SCRIPT="$ROOT_DIR/scripts/sync/sync-space.sh"

NONE_SLUG="__synctest_none__"
REMOTE_SLUG="__synctest_remote__"
NONE_DIR="$LOCAL_DIR/spaces/$NONE_SLUG"
REMOTE_DIR="$LOCAL_DIR/spaces/$REMOTE_SLUG"
BARE_PARENT="$(mktemp -d)"
BARE="$BARE_PARENT/space-backup.git"

cleanup() { rm -rf "$NONE_DIR" "$REMOTE_DIR" "$BARE_PARENT"; }
trap cleanup EXIT

fail() { printf 'FAIL: %b\n' "$*"; exit 1; }

# write_paspoort <dir> <slug> <sync-value>  — minimal but valid space paspoort
write_paspoort() {
	local dir="$1" slug="$2" sync="$3" nid
	mkdir -p "$dir"
	nid="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/spaces/$slug/index" 2>/dev/null || echo "00000000-0000-5000-8000-000000000000")"
	printf -- '---\ntype: space\nslug: %s\nspace-id: %s\nid: %s\nowner: Test\nrelation: client\nconfidential: true\nsync: %s\ntags: [space]\ndate: 2026-06-27\n---\n# %s\n' \
		"$slug" "00000000-1111-4222-8333-444444444444" "$nid" "$sync" "$slug" > "$dir/index.md"
}

vault_shows_spaces() {
	git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
	# spaces/.gitignore is the fail-closed layer and is tracked on purpose;
	# it holds no space content. Any OTHER spaces/ path is a seal breach.
	git -C "$LOCAL_DIR" status --short 2>/dev/null \
		| grep 'spaces/' | grep -qv 'spaces/\.gitignore$'
}

# ============================ Case A: sync: none ============================
write_paspoort "$NONE_DIR" "$NONE_SLUG" "none"
outA="$(bash "$SCRIPT" "$NONE_SLUG" 2>&1)"; rcA=$?
[ "$rcA" -eq 0 ] || fail "Case A: expected exit 0 for sync: none, got $rcA\n$outA"
# Decision reversed 2026-09-04. This asserted the opposite: sync:none must not
# create a repo. The reasoning was that a .git without a remote gives false
# confidence of backup. In practice it tied two different promises together, and
# a space created without a remote stayed unversioned: a 594-line assessment sat
# for an hour with no history, one bad rm from gone. Versioning is local and
# free; backup needs a remote, and sync-space.sh only initialises when there is
# no repo, so this history is carried into the backup rather than replaced.
[ -d "$NONE_DIR/.git" ] || fail "Case A: a space must be versioned locally even with sync: none"
git -C "$NONE_DIR" rev-parse --verify HEAD >/dev/null 2>&1 \
	|| fail "Case A: the space repo exists but holds no commit"
[ "$(git -C "$NONE_DIR" branch --show-current)" = "main" ] \
	|| fail "Case A: space branch is not main; sync-space.sh creates main and they must match"
git -C "$NONE_DIR" remote get-url origin >/dev/null 2>&1 \
	&& fail "Case A: sync: none must not configure a remote"
! vault_shows_spaces || fail "Case A: personal vault git status shows spaces/ content (seal broken)"
echo "  ok[A]: sync: none -> versioned locally on main, no remote, personal vault untouched"

# ============================ Case B: real remote ==========================
git init --bare -b main -q "$BARE"
write_paspoort "$REMOTE_DIR" "$REMOTE_SLUG" "file://$BARE"
mkdir -p "$REMOTE_DIR/learnings"
printf -- '---\ntype: learning\ntags: [secret]\ndate: 2026-06-27\n---\n# client secret\n' > "$REMOTE_DIR/learnings/secret.md"

outB="$(bash "$SCRIPT" "$REMOTE_SLUG" 2>&1)"; rcB=$?
[ "$rcB" -eq 0 ] || fail "Case B: expected exit 0, got $rcB\n$outB"
[ -d "$REMOTE_DIR/.git" ] || fail "Case B: nested .git repo not created"

# The bare remote must now hold a commit with the space's files.
git --git-dir="$BARE" rev-parse --verify main >/dev/null 2>&1 \
	|| fail "Case B: nothing pushed to remote (no 'main' ref)\n$outB"

pushed="$(git --git-dir="$BARE" ls-tree -r --name-only main | sort)"
tracked="$(git -C "$REMOTE_DIR" ls-files | sort)"
[ -n "$pushed" ] || fail "Case B: remote tree is empty"
[ "$pushed" = "$tracked" ] || fail "Case B: pushed set != space tracked set:\n--pushed--\n$pushed\n--tracked--\n$tracked"

# The space's own files are present...
echo "$pushed" | grep -qx "index.md"           || fail "Case B: index.md missing from remote\n$pushed"
echo "$pushed" | grep -qx "learnings/secret.md" || fail "Case B: confidential note missing from remote\n$pushed"
# ...and ONLY the space content (no nesting prefix, no traversal, no vault leak).
if echo "$pushed" | grep -qE '(^|/)spaces/|\.\.'; then
	fail "Case B: remote contains non-space paths (vault leak?):\n$pushed"
fi

# Personal vault still must not see the throwaway space.
! vault_shows_spaces || fail "Case B: personal vault git status shows spaces/ content (seal broken)"
echo "  ok[B]: pushed ONLY the space to its own remote; personal vault untouched"

echo "PASS test-sync-space"
