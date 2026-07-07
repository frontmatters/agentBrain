#!/usr/bin/env bash
# sync-space.sh — back up a SINGLE space to ITS OWN non-personal remote.
#
# A space (local/spaces/<slug>/) is sealed out of the personal vault sync by
# local/.gitignore (spaces/), so it never reaches the personal vault remote. To
# still back up confidential client/employer work, each space is versioned as
# its OWN nested git repo whose origin is the remote named in the paspoort's
# `sync:` field. The nested .git lives inside the gitignored spaces/<slug>/, so
# it stays invisible to the personal vault repo.
#
# Usage:
#   bash scripts/sync-space.sh <slug> [commit-message]
#
#   sync: none (or empty) -> local-only: no commit, no remote, exit 0.
#   sync: <url|name>      -> init/refresh the nested repo and push to THAT
#                            remote ONLY (never the personal vault remote).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

SLUG="${1:-}"
# shellcheck disable=SC2016  # the single quotes are literal in the message; $SLUG still expands (outer "...")
MESSAGE="${2:-Backup space '$SLUG' ($(date -u +%Y-%m-%dT%H:%M:%SZ))}"

# Slug safety (same rule as new-note.sh --space): an empty slug or one containing
# '/', '..', a leading dot, or any char outside [a-z0-9._-] could escape
# local/spaces/<slug>/ and have us operate on the personal vault instead.
case "$SLUG" in
	*[!a-z0-9._-]* | "" | .* | *..* )
		warn "sync-space: invalid space slug: '$SLUG' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')"
		exit 1 ;;
esac

SPACE_DIR="$LOCAL_DIR/spaces/$SLUG"
PASPOORT="$SPACE_DIR/index.md"

if [ ! -d "$SPACE_DIR" ]; then
	warn "sync-space: no such space: $SPACE_DIR"
	exit 1
fi
if [ ! -f "$PASPOORT" ]; then
	warn "sync-space: space has no index.md (paspoort): $PASPOORT"
	exit 1
fi

# --- Read sync: from the paspoort frontmatter (first YAML document only) ------
# Prefer yq (matches brain-extract); fall back to a dependency-free awk reader.
read_sync() {
	local file="$1" val=""
	if command -v yq >/dev/null 2>&1; then
		val="$(yq -r 'select(di==0) | .sync // ""' "$file" 2>/dev/null || echo "")"
	fi
	if [ -z "$val" ] || [ "$val" = "null" ]; then
		val="$(awk '
			NR==1 && $0 ~ /^---[[:space:]]*$/ { infm=1; next }
			infm && $0 ~ /^---[[:space:]]*$/  { exit }
			infm && /^[[:space:]]*sync:[[:space:]]*/ {
				sub(/^[[:space:]]*sync:[[:space:]]*/, "")
				sub(/[[:space:]]+$/, "")
				print; exit
			}
		' "$file")"
	fi
	printf '%s' "$val"
}

SYNC="$(read_sync "$PASPOORT")"
# Strip a single layer of surrounding quotes.
SYNC="${SYNC%\"}"; SYNC="${SYNC#\"}"
SYNC="${SYNC%\'}"; SYNC="${SYNC#\'}"

if [ -z "$SYNC" ] || [ "$SYNC" = "none" ] || [ "$SYNC" = "null" ]; then
	echo "space '$SLUG': local-only, not backed up (sync: none)"
	exit 0
fi

# --- Version the space as its OWN nested git repo -----------------------------
# IMPORTANT: test for a literal .git INSIDE the space dir, NOT `git rev-parse`,
# which would walk UP and find the PERSONAL vault repo (local/.git).
if [ ! -d "$SPACE_DIR/.git" ]; then
	log "space '$SLUG': initialising nested backup repo"
	git -C "$SPACE_DIR" init -b main >/dev/null
fi

# Safety belt: confirm the repo we are about to touch IS the space itself and not
# the personal vault. If git resolves a different toplevel, refuse to continue.
SPACE_REAL="$(cd "$SPACE_DIR" && pwd -P)"
TOP_REAL="$(cd "$(git -C "$SPACE_DIR" rev-parse --show-toplevel)" && pwd -P)"
if [ "$SPACE_REAL" != "$TOP_REAL" ]; then
	warn "sync-space: REFUSING — git toplevel ($TOP_REAL) is not the space dir ($SPACE_REAL); will not touch the personal vault"
	exit 1
fi

# Point origin at the space's OWN remote — never the personal vault remote.
if git -C "$SPACE_DIR" remote get-url origin >/dev/null 2>&1; then
	git -C "$SPACE_DIR" remote set-url origin "$SYNC"
else
	git -C "$SPACE_DIR" remote add origin "$SYNC"
fi

git -C "$SPACE_DIR" add -A
if git -C "$SPACE_DIR" diff --cached --quiet; then
	log "space '$SLUG': no changes since last backup"
else
	git -C "$SPACE_DIR" commit -m "$MESSAGE" >/dev/null
	log "space '$SLUG': committed changes"
fi

if ! git -C "$SPACE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
	log "space '$SLUG': nothing to push (no commits yet)"
	exit 0
fi

BRANCH="$(git -C "$SPACE_DIR" symbolic-ref --short HEAD 2>/dev/null || echo main)"
log "space '$SLUG': pushing to its own remote ($SYNC) [$BRANCH]"
git -C "$SPACE_DIR" push -u origin "$BRANCH"

log "space '$SLUG': backup complete"
