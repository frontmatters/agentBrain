#!/usr/bin/env bash
# new-note.sh — create a brain note with correct frontmatter (including computed UUID5).
# Layer 2 of the agent-discipline enforcement framework: makes "right way" the easy way,
# eliminating the gap where agents type id-fields from memory and get them wrong.
#
# Usage:
#   bash scripts/new-note.sh <type> <vault-relative-path-no-ext> [title] [--platform <csv>]
#
# Examples:
#   bash scripts/new-note.sh learning local/learnings/my-finding "My Great Finding"
#   bash scripts/new-note.sh project local/projects/foo/index "Foo Project"
#   bash scripts/new-note.sh backlog local/backlog/2026-05-24-bar-design "Bar design"
#   bash scripts/new-note.sh spec local/skills/promote/SPEC "Promote skill design"
#   bash scripts/new-note.sh learning local/learnings/pi-on-arm "Pi on ARM" --platform linux-arm64
#
# --platform seeds an optional applicability field (which platform(s) the content
# applies to, not where it was written). Omit it for platform-agnostic notes
# (default: cross-platform). Accepts a comma-separated list, e.g. macos,linux-arm64.
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

# Parse out the optional --platform <csv> flag from anywhere in the args,
# leaving the positional type/path/title interface intact.
PLATFORM_CSV=""
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
case "$TYPE" in
	learning)  TAGS="[learning]"  ; SOURCE="source: session" ;;
	project)   TAGS="[project]"   ; SOURCE="" ;;
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
	[ -n "$PLATFORM_FIELD" ] && echo "$PLATFORM_FIELD"
	[ -n "$SOURCE" ] && echo "$SOURCE"
	[ -n "$EXTRA_FIELDS" ] && echo "$EXTRA_FIELDS"
	echo "id: $UUID"
	echo "---"
	echo ""
	echo "# $TITLE"
	echo ""
} > "$ABS_PATH"

echo "$ABS_PATH"
