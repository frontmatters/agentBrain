#!/usr/bin/env bash
# publish-agentbrain-github.sh — Publish the public GitHub mirror as a CLEAN SNAPSHOT.
#
# The public repo (github.com/frontmatters/agentBrain) deliberately does NOT carry
# the private dev history: that history holds internal hostnames, WIP churn, and
# maintainer identities that should not be exposed. Each publish instead builds the
# validated release archive (tracked files only, no local/, no .git), recreates a
# single clean commit under the project identity, and FORCE-PUSHES it — replacing
# whatever lineage was there. The Gitea dev repo keeps the full history privately.
#
# This is intentional: the public lineage and the dev lineage are decoupled. Do not
# `git push` the dev history here — always re-snapshot.
#
# Usage:
#   bash scripts/publish-agentbrain-github.sh            # build, scan, force-push
#   PUBLISH_DRY_RUN=1 bash scripts/publish-agentbrain-github.sh   # build + stage + scan only
#
# Env:
#   AGENTBRAIN_GITHUB_URL    git URL (default https://github.com/frontmatters/agentBrain.git)
#   AGENTBRAIN_PUBLIC_NAME   commit author name (default: frontmatters)
#   AGENTBRAIN_PUBLIC_EMAIL  commit author email (default: the frontmatters GitHub noreply)
#   AGENTBRAIN_PUBLIC_BRANCH branch (default: main)
#   RELEASE_ZIP              override the archive path (default: ../agentBrain-releases/...)
#
# Requires GitHub push access for the caller (e.g. `gh auth login`). Prints no secrets.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
GITHUB_URL="${AGENTBRAIN_GITHUB_URL:-https://github.com/frontmatters/agentBrain.git}"
BRANCH="${AGENTBRAIN_PUBLIC_BRANCH:-main}"
PUB_NAME="${AGENTBRAIN_PUBLIC_NAME:-frontmatters}"
PUB_EMAIL="${AGENTBRAIN_PUBLIC_EMAIL:-196871115+frontmatters@users.noreply.github.com}"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$VERSION" ] || die "VERSION is empty"

# 1. Build the validated release archive (tracked-only; release.sh enforces the
#    git-ls-files allowlist + a leak gate that aborts if any untracked file lands
#    in the payload, and that the CHANGELOG documents this VERSION).
log "Building release archive for v$VERSION"
"$ROOT_DIR/scripts/privacy-scan.sh" >/dev/null || die "privacy-scan failed on the source tree"
bash "$ROOT_DIR/scripts/release.sh"
ZIP="${RELEASE_ZIP:-$ROOT_DIR/../agentBrain-releases/agentBrain-v${VERSION}.zip}"
[ -f "$ZIP" ] || die "release archive not found: $ZIP"

# 2. Stage a fresh checkout from the archive (auto-cleaned on exit).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
unzip -q "$ZIP" -d "$STAGE"
SRC="$STAGE/agentBrain"
[ -d "$SRC" ] || die "unexpected archive layout (no agentBrain/ dir)"
[ ! -d "$SRC/local" ] || die "archive contains local/ — refusing to publish"
[ ! -d "$SRC/.git" ]  || die "archive contains .git — refusing to publish"

# 3. The staged snapshot IS the release archive: tracked files only, already gated
#    by the source-tree privacy-scan above (personal/project/security content) and
#    by release.sh's git-ls-files allowlist + untracked-leak gate. The structural
#    checks in step 2 (no local/, no .git) are the final guard. We intentionally do
#    NOT hardcode internal hostnames here — that would itself be content to redact.

# 4. Fresh single-commit history under the public identity.
log "Creating clean snapshot commit ($PUB_NAME)"
cd "$SRC"
git init -b "$BRANCH" -q
git config user.name  "$PUB_NAME"
git config user.email "$PUB_EMAIL"
git add -A
git commit -q -m "agentBrain v${VERSION}

Portable, agent-agnostic memory framework for AI coding agents. Public snapshot;
see CHANGELOG.md for the full version history."
git remote add origin "$GITHUB_URL"

if [ "${PUBLISH_DRY_RUN:-0}" = "1" ]; then
	trap - EXIT   # keep the staging dir for inspection
	log "DRY RUN — staged at $SRC ($(git ls-files | wc -l | tr -d ' ') files). Not pushed."
	exit 0
fi

# 5. Force-push the clean snapshot, replacing the public lineage.
log "Force-pushing clean snapshot to $GITHUB_URL ($BRANCH)"
git push --force origin "$BRANCH"

log "Published v$VERSION to GitHub as a clean snapshot."
echo "    $GITHUB_URL ($BRANCH)"
