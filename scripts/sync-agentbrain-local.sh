#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Sync the private agentBrain local/ repository to its private Gitea remote.
# Safe for public repo: this script contains no secrets and reads tokens from the documented Gitea helper.

set -euo pipefail

usage() {
	cat <<EOF
Usage: $0 [--dry-run] [commit-message]

Sync the private local vault and nested sealed-space repositories.

Options:
  --dry-run   show pending vault/space changes without checking, committing, or pushing
  -h, --help  show this help and exit without side effects
EOF
}

DRY_RUN=0
case "${1:-}" in
	-h | --help)
		usage
		exit 0
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--*)
		echo "sync-agentbrain-local: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
CHECK_SCRIPT="${AGENTBRAIN_LOCAL_CHECK_SCRIPT:-$ROOT_DIR/scripts/check-agentbrain-local.sh}"
HELPER_PATH="${GITEA_HELPER_PATH:-$HOME/bin/gitea-helper.sh}"
REMOTE="${AGENTBRAIN_LOCAL_REMOTE:-origin}"
BRANCH="${AGENTBRAIN_LOCAL_BRANCH:-main}"
MESSAGE="${1:-Update private agentBrain local notes}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# Fetch the Gitea token from the keychain helper and export it for the git
# pushes below. Sets an EXIT trap so the token is cleared even on early exit.
ensure_gitea_token() {
	# shellcheck source=/dev/null
	source "$HELPER_PATH" >/dev/null 2>&1
	GITEA_PRIVATE_TOKEN="$(get_gitea_token)"
	export GITEA_PRIVATE_TOKEN
	trap 'unset GITEA_PRIVATE_TOKEN' EXIT
}

# Sync nested space repos. Owned spaces (spaces/<slug>/) are sealed out of the
# vault repo (.gitignore: spaces/) and each carry their OWN git repo + remote —
# so they must be committed and pushed independently. This walks every
# spaces/<slug>/ that has its own .git AND an 'origin' remote, auto-commits any
# pending changes (mirroring the vault flow), and pushes its current branch with
# the same Gitea token. A space without an origin is skipped, and a single space
# failure warns without aborting the rest. Reuses GITEA_PRIVATE_TOKEN from the
# caller — must run after that is exported.
sync_spaces() {
	local spaces_dir="$LOCAL_DIR/spaces" d name branch
	[[ -d "$spaces_dir" ]] || return 0
	for d in "$spaces_dir"/*/; do
		[[ -d "${d}.git" ]] || continue
		name="$(basename "$d")"
		if ! git -C "$d" remote get-url origin >/dev/null 2>&1; then
			warn "space $name: no 'origin' remote — skipped"
			continue
		fi
		log "Syncing space repo: $name"
		git -C "$d" add -A || { warn "space $name: git add failed"; continue; }
		if ! git -C "$d" diff --cached --quiet; then
			git -C "$d" commit -m "chore: sync $name space knowledge" \
				|| { warn "space $name: commit failed"; continue; }
		fi
		branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
		if git -C "$d" -c http.extraHeader="Authorization: token ${GITEA_PRIVATE_TOKEN}" push origin "$branch"; then
			log "space $name pushed ($branch)"
		else
			warn "space $name: push failed"
		fi
	done
}

if [[ ! -d "$LOCAL_DIR/.git" ]]; then
	warn "No git repo found at $LOCAL_DIR"
	exit 1
fi

if [[ "$DRY_RUN" = "1" ]]; then
	log "Dry run: private local vault"
	git -C "$LOCAL_DIR" status --short
	if [[ -d "$LOCAL_DIR/spaces" ]]; then
		for _space in "$LOCAL_DIR"/spaces/*/; do
			[[ -d "${_space}.git" ]] || continue
			log "Dry run: space $(basename "$_space")"
			git -C "$_space" status --short
		done
	fi
	exit 0
fi

if [[ ! -f "$HELPER_PATH" ]]; then
	warn "Gitea helper not found: $HELPER_PATH"
	exit 1
fi

log "Checking private local repo"
cd "$LOCAL_DIR"

# Ensure the note-id pre-commit gate is installed in THIS vault repo. Idempotent
# self-heal so re-clones / new machines get the agent-agnostic id enforcement
# without a manual step.
HOOK_SRC="$ROOT_DIR/scripts/hooks/vault-pre-commit.sh"
HOOK_DST="$LOCAL_DIR/.git/hooks/pre-commit"
if [[ -f "$HOOK_SRC" ]] && ! cmp -s "$HOOK_SRC" "$HOOK_DST" 2>/dev/null; then
	install -m 0755 "$HOOK_SRC" "$HOOK_DST" 2>/dev/null && log "Installed note-id pre-commit gate"
fi

git status --short
if [[ -z "$(git status --porcelain)" ]]; then
	# Vault clean, but a nested space repo may still have its own changes.
	log "No vault changes to sync — checking space repos"
	ensure_gitea_token
	sync_spaces || warn "one or more space repos failed to sync"
	unset GITEA_PRIVATE_TOKEN
	trap - EXIT
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

# Agent-agnostic note-id gate (the pre-commit hook enforces the same on any
# commit path; running it here too covers a missing/bypassed hook). Abort the
# sync rather than commit a note with a mismatched uuid5 id.
if ! bash "$ROOT_DIR/scripts/validate-staged-note-ids.sh"; then
	warn "note-id gate failed — aborting sync. Fix the id(s) above and retry."
	exit 1
fi

git commit -m "$MESSAGE"

log "Pushing to private Gitea remote: $REMOTE $BRANCH"
ensure_gitea_token

git -c http.extraHeader="Authorization: token ${GITEA_PRIVATE_TOKEN}" push "$REMOTE" "$BRANCH"

# Also sync nested owned-space repos to their own remotes (same token).
sync_spaces || warn "one or more space repos failed to sync"

unset GITEA_PRIVATE_TOKEN
trap - EXIT

log "Private local sync complete"
