#!/usr/bin/env bash
# new-note.sh — create a brain note with correct frontmatter (including computed UUID5).
# Layer 2 of the agent-discipline enforcement framework: makes "right way" the easy way,
# eliminating the gap where agents type id-fields from memory and get them wrong.
#
# Usage:
#   bash scripts/new-note.sh <type> <vault-relative-path-no-ext> [title] [--platform <csv>] [--space <slug>]
#
# Examples:
#   bash scripts/new-note.sh learning local/learnings/my-finding "My Great Finding"
#   bash scripts/new-note.sh project local/projects/foo/index "Foo Project"
#   bash scripts/new-note.sh backlog local/backlog/2026-05-24-bar-design "Bar design"
#   bash scripts/new-note.sh spec local/skills/promote/SPEC "Promote skill design"
#   bash scripts/new-note.sh learning local/learnings/pi-on-arm "Pi on ARM" --platform linux-arm64
#   bash scripts/new-note.sh learning learnings/team-finding "Team finding" --space acme
#
# --platform seeds an optional applicability field (which platform(s) the content
# applies to, not where it was written). Omit it for platform-agnostic notes
# (default: cross-platform). Accepts a comma-separated list, e.g. macos,linux-arm64.
#
# --space writes the note INTO a space: the type-relative path is rooted at
# local/spaces/<slug>/, a `space: <slug>` frontmatter field is added, and the
# computed UUID5 matches the real (spaced) write path. A leading `local/` on the
# positional path is stripped before rooting it under the space. When no --space
# is given but a space is active (see scripts/active-space.sh), the note defaults
# into that active space.
#
# Writes to <vault>/<path>.md if it doesn't exist, refuses to overwrite.
# Prints the absolute path on success. Use as scaffold — fill body via Edit/Write after.

set -euo pipefail

if [ $# -lt 2 ]; then
	cat >&2 <<EOF
Usage: $0 <type> <vault-relative-path-no-ext> [title]
  type: learning | project | backlog | feedback | reference | session | spec
  path: e.g. local/learnings/my-slug  (without .md)
  title: optional H1, defaults to deslug of basename
EOF
	exit 2
fi

# Parse out the optional --platform <csv> / --space <slug> flags from anywhere in
# the args, leaving the positional type/path/title interface intact.
PLATFORM_CSV=""
SPACE_SLUG=""
SPACE_GIVEN=0
STRICT=0
POSITIONAL=()
while [ $# -gt 0 ]; do
	case "$1" in
		--platform)
			PLATFORM_CSV="${2:-}"
			shift 2
			;;
		--platform=*)
			PLATFORM_CSV="${1#--platform=}"
			shift
			;;
		--space | --context)
			SPACE_SLUG="${2:-}"
			SPACE_GIVEN=1
			shift 2
			;;
		--space=* | --context=*)
			SPACE_SLUG="${1#*=}"
			SPACE_GIVEN=1
			shift
			;;
		--strict)
			STRICT=1
			shift
			;;
		*)
			POSITIONAL+=("$1")
			shift
			;;
	esac
done
set -- "${POSITIONAL[@]}"

TYPE="$1"
REL_PATH_NO_EXT="$2"
TITLE="${3:-}"

# Per-write context inference. Replaces the old global active-space marker, which
# married work-context to storage and leaked across parallel sessions (see the
# spaces-context-model design). When no explicit --space/--context was given, infer
# the write context from PATH-based + explicit signals — env AGENTBRAIN_CONTEXT, the
# CWD's code-root, the git remote — NEVER from content. system/lib/context.sh owns
# the logic; the resolved slug still flows through the path-escape guard below.
#   confident slug → write into that space
#   ambiguous      → refuse (the file's path and frontmatter disagree)
#   unknown        → main vault (default); with --strict / AGENTBRAIN_STRICT_CONTEXT=1, refuse
if [ "$SPACE_GIVEN" = "0" ]; then
	_NN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	_CTX_LIB="$_NN_DIR/../system/lib/context.sh"
	if [ -f "$_CTX_LIB" ]; then
		# shellcheck source=/dev/null
		. "$_CTX_LIB"
		_CTX="$(infer_context 2>/dev/null || echo unknown)"
	else
		_CTX="unknown" # no context lib (partial checkout) → main-vault default
	fi
	case "$_CTX" in
		unknown)
			if [ "$STRICT" = "1" ] || [ "${AGENTBRAIN_STRICT_CONTEXT:-0}" = "1" ]; then
				echo "new-note: write context is unknown and strict mode is on — refusing to guess." >&2
				echo "         Pass --context <slug> (or --space), or set AGENTBRAIN_CONTEXT=<slug>." >&2
				exit 3
			fi
			;; # default → main vault (no space field)
		ambiguous)
			echo "new-note: write context is ambiguous — refusing to guess where this note belongs." >&2
			echo "         Pass --context <slug> (or --space) explicitly." >&2
			exit 3
			;;
		*)
			SPACE_SLUG="$_CTX"
			SPACE_GIVEN=1
			;;
	esac
fi

# --space: root the (type-relative) positional path under local/spaces/<slug>/.
# Strip a leading "local/" if the caller included one so we don't double it.
# Validate the slug first: an empty slug or one containing '/', '..', a leading
# dot, or any char outside [a-z0-9._-] could write OUTSIDE local/spaces/<slug>/
# (e.g. --space ../personal escaping into the personal vault), defeating the seal.
SPACE_FIELD=""
if [ "$SPACE_GIVEN" = "1" ]; then
	case "$SPACE_SLUG" in
		*[!a-z0-9._-]* | "" | .* | *..* )
			echo "new-note: invalid --space slug: '$SPACE_SLUG' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')" >&2
			exit 2 ;;
	esac
	SPACE_REL="${REL_PATH_NO_EXT#local/}"
	REL_PATH_NO_EXT="local/spaces/${SPACE_SLUG}/${SPACE_REL}"
	SPACE_FIELD="space: ${SPACE_SLUG}"
fi

# Project notes live at <dir>/index.md. If the caller passed the project dir
# (or any non-"index" leaf), append /index so the computed UUID5 matches the
# real file path. Closes the #1 source of project-note id-mismatches: hashing
# the directory path instead of .../index. Transparent — we say so on stderr.
if [ "$TYPE" = "project" ] && [ "$(basename "$REL_PATH_NO_EXT")" != "index" ]; then
	echo "new-note: project notes live at <dir>/index — using ${REL_PATH_NO_EXT}/index" >&2
	REL_PATH_NO_EXT="${REL_PATH_NO_EXT}/index"
fi

# Normalize "macos, linux-arm64" / "macos,linux-arm64" → "[macos, linux-arm64]".
PLATFORM_FIELD=""
if [ -n "$PLATFORM_CSV" ]; then
	NORM="$(echo "$PLATFORM_CSV" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | paste -sd, - | sed 's/,/, /g')"
	PLATFORM_FIELD="platform: [${NORM}]"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABS_PATH="${ROOT_DIR}/${REL_PATH_NO_EXT}.md"

if [ -e "$ABS_PATH" ]; then
	echo "Refuse to overwrite existing: $ABS_PATH" >&2
	exit 1
fi

mkdir -p "$(dirname "$ABS_PATH")"

UUID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL_PATH_NO_EXT")"
TODAY="$(date -u +%Y-%m-%d)"

# Default title = deslug last segment of path
if [ -z "$TITLE" ]; then
	SLUG="$(basename "$REL_PATH_NO_EXT")"
	TITLE="$(echo "$SLUG" | tr '-' ' ' | sed -E 's/(^| )./\U&/g')"
fi

# Per-type tags + source + per-type extra frontmatter fields (e.g. version for specs).
EXTRA_FIELDS=""
STATUS_FIELD=""
case "$TYPE" in
	learning)  TAGS="[learning]"  ; SOURCE="source: session" ;;
	project)   TAGS="[project]"   ; SOURCE="" ; STATUS_FIELD="status: active" ;;
	backlog)   TAGS="[backlog]"   ; SOURCE="source: session" ;;
	feedback)  TAGS="[feedback]"  ; SOURCE="source: session" ;;
	reference) TAGS="[reference]" ; SOURCE="" ;;
	session)   TAGS="[session]"   ; SOURCE="" ;;
	spec)      TAGS="[spec]"      ; SOURCE="source: session"
	           EXTRA_FIELDS="version: 1.0.0" ;;
	*) echo "Unknown type: $TYPE (use: learning|project|backlog|feedback|reference|session|spec)" >&2; exit 2 ;;
esac

{
	echo "---"
	echo "date: $TODAY"
	echo "type: $TYPE"
	echo "tags: $TAGS"
	[ -n "$STATUS_FIELD" ] && echo "$STATUS_FIELD"
	[ -n "$PLATFORM_FIELD" ] && echo "$PLATFORM_FIELD"
	[ -n "$SPACE_FIELD" ] && echo "$SPACE_FIELD"
	[ -n "$SOURCE" ] && echo "$SOURCE"
	[ -n "$EXTRA_FIELDS" ] && echo "$EXTRA_FIELDS"
	echo "id: $UUID"
	echo "---"
	echo ""
	echo "# $TITLE"
	echo ""
} > "$ABS_PATH"

echo "$ABS_PATH"
