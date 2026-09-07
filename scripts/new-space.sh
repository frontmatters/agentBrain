#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# new-space.sh — scaffold a sealed agentBrain space paspoort (local/spaces/<slug>/index.md).
#
# A space is a per-owner (client/employer/…) compartment of local/, sealed out of
# the personal vault by local/.gitignore and versioned as its own nested git repo.
# This writes ONLY the paspoort; it does not create the nested repo — run
# `scripts/sync/sync-space.sh <slug>` after setting `sync:` to a remote to seal + back up.
#
# Usage:
#   scripts/new-space.sh <slug> --owner "<name>" --relation <relation> \
#       [--aliases a,b] [--code-roots ~/p1,~/p2] [--sync <url|none>]
#
# Fields it fills:
#   space-id : a fresh random UUID (the space's stable identity)
#   id       : the path-derived UUID5 (note-schema invariant; validated everywhere)
#   relation : free lowercase token — existing spaces use client | employer | personal-family
#   sync     : remote URL to back up to, or `none` (local-only, default)
#
# Refuses to overwrite an existing paspoort. Prints next steps on success.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
	sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	exit "${1:-2}"
}

SLUG=""
OWNER=""
RELATION=""
ALIASES=""
CODE_ROOTS=""
SYNC="none"

while [ $# -gt 0 ]; do
	# shellcheck disable=SC2015  # intended: first bare arg fills SLUG, any later bare arg is the error case
	case "$1" in
		--owner)       OWNER="${2:-}"; shift 2 ;;
		--owner=*)     OWNER="${1#--owner=}"; shift ;;
		--relation)    RELATION="${2:-}"; shift 2 ;;
		--relation=*)  RELATION="${1#--relation=}"; shift ;;
		--aliases)     ALIASES="${2:-}"; shift 2 ;;
		--aliases=*)   ALIASES="${1#--aliases=}"; shift ;;
		--code-roots)  CODE_ROOTS="${2:-}"; shift 2 ;;
		--code-roots=*) CODE_ROOTS="${1#--code-roots=}"; shift ;;
		--canonical)   CANONICAL="${2:-}"; shift 2 ;;
		--canonical=*) CANONICAL="${1#--canonical=}"; shift ;;
		--sync)        SYNC="${2:-}"; shift 2 ;;
		--sync=*)      SYNC="${1#--sync=}"; shift ;;
		-h|--help)     usage 0 ;;
		-*)            echo "new-space: unknown flag: $1" >&2; usage 2 ;;
		*)             [ -z "$SLUG" ] && SLUG="$1" && shift || { echo "new-space: unexpected arg: $1" >&2; usage 2; } ;;
	esac
done

# Slug guard — same rule as new-note.sh --space: reject anything that could escape
# local/spaces/<slug>/ (empty, '/', '..', leading dot, or chars outside [a-z0-9._-]).
case "$SLUG" in
	*[!a-z0-9._-]* | "" | .* | *..* )
		echo "new-space: invalid slug: '$SLUG' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')" >&2
		exit 2 ;;
esac
[ -n "$OWNER" ]    || { echo "new-space: --owner is required" >&2; usage 2; }
[ -n "$RELATION" ] || { echo "new-space: --relation is required (e.g. client, employer, personal-family)" >&2; usage 2; }

REL_NO_EXT="vault/spaces/${SLUG}/index"
ABS_PATH="${ROOT_DIR}/${REL_NO_EXT}.md"
if [ -e "$ABS_PATH" ]; then
	echo "new-space: refuse to overwrite existing paspoort: $ABS_PATH" >&2
	exit 1
fi

SPACE_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
ID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL_NO_EXT")"
TODAY="$(date -u +%Y-%m-%d)"

# Normalize a comma list "a, b" -> "[a, b]" (empty -> "[]").
fmt_list() {
	local csv="$1" norm
	norm="$(printf '%s' "$csv" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | paste -sd, - | sed 's/,/, /g')"
	printf '[%s]' "$norm"
}

mkdir -p "$(dirname "$ABS_PATH")"
{
	echo "---"
	echo "type: space"
	echo "slug: ${SLUG}"
	echo "space-id: ${SPACE_ID}"
	echo "id: ${ID}"
	echo "owner: ${OWNER}"
	echo "relation: ${RELATION}"
	echo "aliases: $(fmt_list "$ALIASES")"
	echo "confidential: true"
	echo "sync: ${SYNC}"
	echo "code-roots: $(fmt_list "$CODE_ROOTS")"
		[ -n "${CANONICAL:-}" ] && echo "canonical: ${CANONICAL}"
	echo "tags: [space, ${RELATION}, ${SLUG}]"
	echo "date: ${TODAY}"
	echo "---"
	echo ""
	echo "# ${OWNER} — space"
	echo ""
	echo "Sealed compartment for ${OWNER} (${RELATION}). Confidential: kept out of the"
	echo "personal vault and public layer; backed up only to its own remote via sync-space.sh."
	echo ""
} > "$ABS_PATH"

# Version it from the start, remote or not. Versioning is local and free;
# backup needs a remote, and tying the two together meant a space created with
# sync:none stayed unversioned until somebody remembered to seal it. A 594-line
# assessment sat that way for an hour with no history behind it.
#
# sync-space.sh only initialises when there is no repo yet, so this history is
# carried into the backup when a remote is added later rather than replaced.
# Branch -b main to match what sync-space.sh creates; without it the space
# inherits whatever the machine's git default happens to be, and two of six
# existing spaces are on master for exactly that reason.
SPACE_DIR="$(dirname "$ABS_PATH")"
if [ ! -e "$SPACE_DIR/.git" ]; then
	if git -C "$SPACE_DIR" init -q -b main . 2>/dev/null; then
		echo "new-space: versioned '${SLUG}' locally (no remote yet; sync-space.sh adds one)" >&2
	fi
fi

# Fail-closed second layer, one level up. The `spaces/*` rule in local/.gitignore
# states the intent; this holds when that rule is edited away or a checkout
# arrives without it. It constrains nothing inside a space: a nested repository
# never consults a parent's ignore rules.
SPACES_ROOT="$(dirname "$(dirname "$ABS_PATH")")"
if [ ! -f "$SPACES_ROOT/.gitignore" ]; then
	printf '%s\n' \
		'# Fail-closed: everything here is invisible to the vault repo except this' \
		'# file. A sealed compartment cannot reach the personal remote even if the' \
		'# rule one level up is lost. Each space is its own repo and is unaffected.' \
		'*' \
		'!.gitignore' > "$SPACES_ROOT/.gitignore"
	echo "new-space: wrote the fail-closed spaces/.gitignore" >&2
fi

echo "$ABS_PATH"
echo "new-space: created paspoort for '${SLUG}' (space-id ${SPACE_ID})" >&2
if [ "$SYNC" = "none" ]; then
	echo "new-space: sync is 'none' (local-only, no backup). To seal to a private remote:" >&2
	echo "           1) create a PRIVATE repo named '${SLUG}-space' on your git host" >&2
	echo "           2) set the paspoort 'sync:' to its URL" >&2
	echo "           3) bash scripts/sync/sync-space.sh ${SLUG}" >&2
else
	echo "new-space: next — bash scripts/sync/sync-space.sh ${SLUG}   (seal + push to ${SYNC})" >&2
fi
