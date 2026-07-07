#!/usr/bin/env bash
# test-sync-space.sh — proves scripts/sync-space.sh backs a space up to ITS OWN
# non-personal remote, never the personal vault, and only when sync: is a remote.
#
#   Case A (sync: none): no commit, no nested repo, exit 0; the personal vault's
#                        `git status` shows nothing under spaces/.
#   Case B (real remote): pushes the space — and ONLY the space — to a throwaway
#                        file:// bare repo; the personal vault stays untouched.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
SCRIPT="$ROOT_DIR/scripts/sync-space.sh"

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
	git -C "$LOCAL_DIR" status --short 2>/dev/null | grep -q 'spaces/'
}

# ============================ Case A: sync: none ============================
write_paspoort "$NONE_DIR" "$NONE_SLUG" "none"
outA="$(bash "$SCRIPT" "$NONE_SLUG" 2>&1)"; rcA=$?
[ "$rcA" -eq 0 ] || fail "Case A: expected exit 0 for sync: none, got $rcA\n$outA"
[ ! -d "$NONE_DIR/.git" ] || fail "Case A: sync: none must not create a nested .git repo"
! vault_shows_spaces || fail "Case A: personal vault git status shows spaces/ content (seal broken)"
echo "  ok[A]: sync: none -> exit 0, no nested repo, personal vault untouched"

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
