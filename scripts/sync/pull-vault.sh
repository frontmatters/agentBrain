#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# pull-vault.sh — bring the vault up to date with its remote at session start.
#
# sync-vault.sh commits and pushes; nothing pulled. On a second machine every
# session therefore started on stale notes, and two machines editing the same
# note met in a merge conflict (2026-09-07). This is the other half: a
# fast-forward-only pull, quiet by contract, never failing a session.
#
# Output contract (stdout goes into the agent's session context):
#   - nothing when the vault is already current, offline, or has no remote;
#   - one line when notes came in ("vault: pulled N commit(s)");
#   - one line when the vault has diverged and needs a human ("vault: N local
#     and M remote commit(s) diverged; run sync-vault.sh, then merge").
#   Never the remote URL (a private LAN address, see check-session-update-quiet).
#
# Usage: bash scripts/sync/pull-vault.sh [--strict]
#   --strict  exit non-zero on divergence or a failed fetch (for scripts); the
#             default exits 0 no matter what, for session hooks.
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1
fail() { [ "$STRICT" -eq 1 ] && exit 1; exit 0; }

# PULL_VAULT_DIR overrides (tests point it at a fixture); otherwise the vault
# of this checkout, as scripts/lib/vault.sh resolves it.
V="${PULL_VAULT_DIR:-}"
if [ -z "$V" ]; then
	# shellcheck source=../lib/vault.sh
	. "$ROOT/scripts/lib/vault.sh"
	V="${VAULT_DIR:-}"
fi
[ -n "$V" ] && [ -d "$V/.git" ] || exit 0
REMOTE="${AGENTBRAIN_LOCAL_REMOTE:-origin}"
git -C "$V" remote get-url "$REMOTE" >/dev/null 2>&1 || exit 0

# The Gitea token, when the documented helper is here; a public or LAN remote
# without one still works. The header goes to git only, never to stdout.
HDR=()
HELPER="${GITEA_HELPER_PATH:-$HOME/bin/gitea-helper.sh}"
if [ -f "$HELPER" ]; then
	# shellcheck source=/dev/null
	tok="$( (source "$HELPER" >/dev/null 2>&1; get_gitea_token 2>/dev/null) || true)"
	[ -n "$tok" ] && HDR=(-c "http.extraHeader=Authorization: token $tok")
fi

# Bounded fetch: a session must not hang on an unreachable LAN host.
budget="${PULL_VAULT_BUDGET:-16}"   # half-seconds
# ${HDR[@]+"${HDR[@]}"}: bash 3.2 (macOS /bin/bash) treats an empty array as unbound under set -u.
GIT_TERMINAL_PROMPT=0 git -C "$V" ${HDR[@]+"${HDR[@]}"} fetch --quiet "$REMOTE" 2>/dev/null &
fpid=$!; i=0
while [ "$i" -lt "$budget" ]; do kill -0 "$fpid" 2>/dev/null || break; sleep 0.5; i=$((i+1)); done
if kill -0 "$fpid" 2>/dev/null; then kill "$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null; fail; fi
wait "$fpid" || fail

branch="$(git -C "$V" branch --show-current 2>/dev/null)"; [ -n "$branch" ] || exit 0
git -C "$V" rev-parse --verify -q "refs/remotes/$REMOTE/$branch" >/dev/null || exit 0
behind="$(git -C "$V" rev-list --count "HEAD..$REMOTE/$branch" 2>/dev/null || echo 0)"
ahead="$(git -C "$V" rev-list --count "$REMOTE/$branch..HEAD" 2>/dev/null || echo 0)"
[ "$behind" -eq 0 ] && exit 0
if [ "$ahead" -ne 0 ]; then
	echo "vault: $ahead local and $behind remote commit(s) diverged; run scripts/sync/sync-vault.sh, then merge"
	fail
fi
if git -C "$V" merge --ff-only --quiet "$REMOTE/$branch" 2>/dev/null; then
	echo "vault: pulled $behind commit(s)"
	exit 0
fi
echo "vault: $behind remote commit(s) waiting, but local changes are in the way; commit them (sync-vault.sh) and pull again"
fail
