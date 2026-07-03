#!/usr/bin/env bash
# Sync the private agentBrain local/ repository to its private Gitea remote.
# Safe for public repo: this script contains no secrets and reads tokens from the documented Gitea helper.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
CHECK_SCRIPT="${AGENTBRAIN_LOCAL_CHECK_SCRIPT:-$ROOT_DIR/scripts/check-agentbrain-local.sh}"
HELPER_PATH="${GITEA_HELPER_PATH:-$HOME/bin/gitea-helper.sh}"
REMOTE="${AGENTBRAIN_LOCAL_REMOTE:-origin}"
BRANCH="${AGENTBRAIN_LOCAL_BRANCH:-main}"
MESSAGE="${1:-Update private agentBrain local notes}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

if [[ ! -d "$LOCAL_DIR/.git" ]]; then
	warn "No git repo found at $LOCAL_DIR"
	exit 1
fi

if [[ ! -f "$HELPER_PATH" ]]; then
	warn "Gitea helper not found: $HELPER_PATH"
	exit 1
fi

log "Checking private local repo"
cd "$LOCAL_DIR"

git status --short
if [[ -z "$(git status --porcelain)" ]]; then
	log "No local changes to sync"
	exit 0
fi

if [[ -x "$CHECK_SCRIPT" ]]; then
	log "Running private local sanity check"
	"$CHECK_SCRIPT"
fi

log "Committing private local changes"
git add -A
if git diff --cached --quiet; then
	log "No staged changes after git add"
	exit 0
fi

git commit -m "$MESSAGE"

log "Pushing to private Gitea remote: $REMOTE $BRANCH"
# shellcheck source=/dev/null
source "$HELPER_PATH" >/dev/null 2>&1

GITEA_PRIVATE_TOKEN="$(get_gitea_token)"
export GITEA_PRIVATE_TOKEN
trap 'unset GITEA_PRIVATE_TOKEN' EXIT

git -c http.extraHeader="Authorization: token ${GITEA_PRIVATE_TOKEN}" push "$REMOTE" "$BRANCH"

unset GITEA_PRIVATE_TOKEN
trap - EXIT

log "Private local sync complete"
