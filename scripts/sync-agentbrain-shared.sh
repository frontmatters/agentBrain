#!/usr/bin/env bash
# Sync the shared/ scope to its git remote: gate -> pull --rebase -> gate -> push.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_DIR="${AGENTBRAIN_SHARED_DIR:-$ROOT_DIR/shared}"
CHECK="${ROOT_DIR}/scripts/check-agentbrain-shared.sh"
REMOTE="${AGENTBRAIN_SHARED_REMOTE_NAME:-origin}"
BRANCH="${AGENTBRAIN_SHARED_BRANCH:-main}"
MESSAGE="${1:-Update shared agentBrain notes}"
log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

[[ -d "$SHARED_DIR/.git" ]] || { warn "No git repo at $SHARED_DIR"; exit 1; }
cd "$SHARED_DIR"

# Pre-push gate over working tree.
AGENTBRAIN_SHARED_DIR="$SHARED_DIR" bash "$CHECK" || exit 1

# Fetch + incoming gate + rebase (abort on conflict).
log "Fetching $REMOTE/$BRANCH"
git fetch "$REMOTE" "$BRANCH" 2>/dev/null || warn "Fetch failed — remote unreachable? Working offline; skipping pull."
if git rev-parse --verify -q FETCH_HEAD >/dev/null; then
	AGENTBRAIN_SHARED_DIR="$SHARED_DIR" bash "$CHECK" --incoming || { warn "Incoming refs blocked by secret-gate. Aborting."; exit 1; }
	if ! git rebase "FETCH_HEAD" 2>/dev/null; then
		git rebase --abort 2>/dev/null || true
		warn "Divergent history / conflict. Resolve manually (git pull --rebase) then re-run. Aborted (no force)."
		exit 1
	fi
fi

# Commit local changes.
if [[ -z "$(git status --porcelain)" ]]; then log "No local changes to sync"; exit 0; fi
git add -A
git -c user.email="${AGENTBRAIN_GIT_EMAIL:-brain@local}" -c user.name="${AGENTBRAIN_GIT_NAME:-agentBrain}" commit -qm "$MESSAGE"

# Push — per-scope credential. NO_TOKEN path for local/bare remotes & tests.
log "Pushing to $REMOTE/$BRANCH"
if [[ "${AGENTBRAIN_SHARED_NO_TOKEN:-0}" == "1" ]]; then
	git push "$REMOTE" "HEAD:$BRANCH"
else
	HELPER="${AGENTBRAIN_SHARED_HELPER:-$HOME/bin/gitea-helper.sh}"
	[[ -f "$HELPER" ]] || { warn "Scope credential helper not found: $HELPER"; exit 1; }
	# shellcheck source=/dev/null
	source "$HELPER" >/dev/null 2>&1
	TOKEN="$(get_gitea_token)"; export TOKEN
	trap 'unset TOKEN' EXIT
	git -c http.extraHeader="Authorization: token ${TOKEN}" push "$REMOTE" "HEAD:$BRANCH"
	unset TOKEN; trap - EXIT
fi
log "Shared sync complete"
