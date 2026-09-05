#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# new-note.sh — create a brain note with correct frontmatter (including computed UUID5).
# Layer 2 of the agent-discipline enforcement framework: makes "right way" the easy way,
# eliminating the gap where agents type id-fields from memory and get them wrong.
#
# Usage:
#   bash scripts/new-note.sh <type> <vault-relative-path-no-ext> [title] [--platform <csv>] [--space <slug>] [--from <path>]
#
# Examples:
#   bash scripts/new-note.sh learning vault/learnings/my-finding "My Great Finding"
#   bash scripts/new-note.sh project vault/projects/foo/index "Foo Project"
#   bash scripts/new-note.sh backlog vault/backlog/2026-05-24-bar-design "Bar design"
#   bash scripts/new-note.sh spec vault/skills/promote/SPEC "Promote skill design"
#   bash scripts/new-note.sh learning vault/learnings/pi-on-arm "Pi on ARM" --platform linux-arm64
#   bash scripts/new-note.sh learning learnings/team-finding "Team finding" --space acme
#   bash scripts/new-note.sh project vault/projects/foo "Foo" --from /path/to/owner/repo
#
# --platform seeds an optional applicability field (which platform(s) the content
# applies to, not where it was written). Omit it for platform-agnostic notes
# (default: cross-platform). Accepts a comma-separated list, e.g. macos,linux-arm64.
#
# --space writes the note INTO a space: the type-relative path is rooted at
# vault/spaces/<slug>/, a `space: <slug>` frontmatter field is added, and the
# computed UUID5 matches the real (spaced) write path. A leading `vault/` on the
# positional path is stripped before rooting it under the space. Without an
# explicit space, context is inferred per write from --from, env, CWD code-root,
# or git remote; there is no shared active-space session marker.
#
# --from infers context from the code-root containing the supplied file or directory.
# It is useful when the agent harness CWD differs from the repo being worked on.
#
# Writes to <vault>/<path>.md if it doesn't exist, refuses to overwrite.
# Prints the absolute path on success. Use as scaffold — fill body via Edit/Write after.

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
	cat <<EOF
Usage: $0 <type> <vault-relative-path-no-ext> [title] [options]
  --platform <csv>     optional platform applicability
  --space <slug>       explicit sealed-space context (alias: --context)
  --from <path>        infer context from this repo/file instead of the harness CWD
  --strict             refuse when context cannot be inferred
EOF
	exit 0
fi

if [ $# -lt 2 ]; then
	cat >&2 <<EOF
Usage: $0 <type> <vault-relative-path-no-ext> [title]
  type: learning | project | backlog | feedback | reference | session | spec | task | decisions
  path: e.g. vault/learnings/my-slug  (without .md)
  title: optional H1, defaults to deslug of basename
EOF
	exit 2
fi

# Parse optional flags from anywhere in the args, leaving the positional
# type/path/title interface intact.
PLATFORM_CSV=""
SPACE_SLUG=""
SPACE_GIVEN=0
FROM_PATH=""
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
		--from | --workdir)
			FROM_PATH="${2:-}"
			shift 2
			;;
		--from=* | --workdir=*)
			FROM_PATH="${1#*=}"
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

# vault/ is the link's name on disk; local/ is the older name and still accepted.
# The id is the same either way: uuid5-gen.sh folds vault/ to local/ before hashing.
case "$REL_PATH_NO_EXT" in
	local/*) REL_PATH_NO_EXT="vault/${REL_PATH_NO_EXT#local/}" ;;
esac

# A fully-qualified space path is accepted for compatibility, but normalized
# before the regular --space rooting below. This prevents callers that also set
# AGENTBRAIN_CONTEXT/--context from creating a duplicate spaces/<slug> segment.
PATH_SPACE_SLUG=""
PATH_SPACE_REL=""
case "$REL_PATH_NO_EXT" in
	vault/spaces/*/*)
		_PATH_SPACE_TAIL="${REL_PATH_NO_EXT#vault/spaces/}"
		PATH_SPACE_SLUG="${_PATH_SPACE_TAIL%%/*}"
		PATH_SPACE_REL="${_PATH_SPACE_TAIL#*/}"
		;;
	vault/spaces/*)
		echo "new-note: a space path must include a note path below vault/spaces/<slug>/" >&2
		exit 2
		;;
esac

FROM_DIR=""
if [ -n "$FROM_PATH" ]; then
	if [ -d "$FROM_PATH" ]; then
		FROM_DIR="$(cd "$FROM_PATH" && pwd)"
	elif [ -f "$FROM_PATH" ]; then
		FROM_DIR="$(cd "$(dirname "$FROM_PATH")" && pwd)"
	else
		echo "new-note: --from path does not exist: $FROM_PATH" >&2
		exit 2
	fi
fi

# Per-write context inference. Replaces the old global active-space marker, which
# married work-context to storage and leaked across parallel sessions (see the
# spaces-context-model design). When no explicit --space/--context was given, infer
# the write context from PATH-based + explicit signals — env AGENTBRAIN_CONTEXT, the
# CWD's code-root, the git remote — NEVER from content. system/lib/context.sh owns
# the logic; the resolved slug still flows through the path-escape guard below.
#   confident slug → write into that space
#   ambiguous      → refuse (the file's path and frontmatter disagree)
#   unknown        → main vault (default); with --strict / AGENTBRAIN_STRICT_CONTEXT=1, refuse
_NN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CTX_LIB="$_NN_DIR/../system/lib/context.sh"
if [ -f "$_CTX_LIB" ]; then
	# shellcheck source=/dev/null
	. "$_CTX_LIB"
fi
if [ "$SPACE_GIVEN" = "0" ]; then
	if [ -f "$_CTX_LIB" ]; then
		_CTX_FILE=""
		[ -n "$PATH_SPACE_SLUG" ] && _CTX_FILE="$_NN_DIR/../${REL_PATH_NO_EXT}.md"
		_CTX="$(infer_context "$_CTX_FILE" "${FROM_DIR:-$PWD}" 2>/dev/null || echo unknown)"
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

# Resolve --from independently from explicit env/flag context. If both identify
# owners, they must agree; an unknown source path contributes no owner signal.
if [ -n "$FROM_DIR" ] && [ -f "${_CTX_LIB:-}" ]; then
	_FROM_CTX="$(
		(unset AGENTBRAIN_CONTEXT AGENTBRAIN_SPACE; infer_context "" "$FROM_DIR") 2>/dev/null || echo unknown
	)"
	case "$_FROM_CTX" in
		unknown) : ;;
		ambiguous)
			echo "new-note: --from context is ambiguous — refusing to route the note" >&2
			exit 3
			;;
		*)
			if [ "$SPACE_GIVEN" = "1" ] && [ "$SPACE_SLUG" != "$_FROM_CTX" ]; then
				echo "new-note: context '$SPACE_SLUG' conflicts with --from context '$_FROM_CTX'" >&2
				exit 3
			fi
			;;
	esac
fi

# Same path/context is normalized to one space root. Conflicting owner signals
# fail before any directory is created.
if [ -n "$PATH_SPACE_SLUG" ]; then
	if [ "$SPACE_GIVEN" = "1" ] && [ "$SPACE_SLUG" != "$PATH_SPACE_SLUG" ]; then
		echo "new-note: context '$SPACE_SLUG' conflicts with path space '$PATH_SPACE_SLUG'" >&2
		exit 3
	fi
	SPACE_SLUG="$PATH_SPACE_SLUG"
	SPACE_GIVEN=1
	REL_PATH_NO_EXT="$PATH_SPACE_REL"
fi

# --space: root the (type-relative) positional path under vault/spaces/<slug>/.
# Strip a leading "vault/" if the caller included one so we don't double it.
# Validate the slug first: an empty slug or one containing '/', '..', a leading
# dot, or any char outside [a-z0-9._-] could write OUTSIDE vault/spaces/<slug>/
# (e.g. --space ../personal escaping into the personal vault), defeating the seal.
SPACE_FIELD=""
if [ "$SPACE_GIVEN" = "1" ]; then
	case "$SPACE_SLUG" in
		*[!a-z0-9._-]* | "" | .* | *..* )
			echo "new-note: invalid --space slug: '$SPACE_SLUG' (allowed: lowercase a-z 0-9 . _ -, no '/' or '..')" >&2
			exit 2 ;;
	esac
	SPACE_REL="${REL_PATH_NO_EXT#vault/}"
	REL_PATH_NO_EXT="vault/spaces/${SPACE_SLUG}/${SPACE_REL}"
	SPACE_FIELD="space: ${SPACE_SLUG}"
fi

# Guard: every note lives under vault/ (the vault). A caller that omits the prefix
# (e.g. "learnings/foo" instead of "vault/learnings/foo") would otherwise write to
# the CHECKOUT ROOT — outside the vault, git-untracked, and invisible to
# validate-note-id.sh (which only checks vault/*), so the path-derived UUID5 silently
# mismatches the real vault path and only detonates when the note is later moved in.
# Auto-prefix instead of refusing: keeps "the right way the easy way" (see header) and
# guarantees the computed id matches the validator. Space-writes already root under
# vault/spaces/ above, so this is a no-op for them.
case "$REL_PATH_NO_EXT" in
	vault/*) : ;;
	*)
		echo "new-note: path '${REL_PATH_NO_EXT}' is not under vault/ — auto-prefixing to 'vault/${REL_PATH_NO_EXT}'" >&2
		REL_PATH_NO_EXT="vault/${REL_PATH_NO_EXT}"
		;;
esac

# Project notes live at <dir>/index.md. If the caller passed the project dir
# (or any non-"index" leaf), append /index so the computed UUID5 matches the
# real file path. Closes the #1 source of project-note id-mismatches: hashing
# the directory path instead of .../index. Transparent — we say so on stderr.
if [ "$TYPE" = "project" ] && [ "$(basename "$REL_PATH_NO_EXT")" != "index" ]; then
	echo "new-note: project notes live at <dir>/index — using ${REL_PATH_NO_EXT}/index" >&2
	REL_PATH_NO_EXT="${REL_PATH_NO_EXT}/index"
fi

# Refuse supplemental notes inside a project folder that has no canonical
# index.md. This prevents new malformed project directories while leaving
# historical folders untouched until they are explicitly consolidated.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_INDEX_REL=""
case "$REL_PATH_NO_EXT" in
	vault/projects/*/*)
		_PROJECT_TAIL="${REL_PATH_NO_EXT#vault/projects/}"
		_PROJECT_SLUG="${_PROJECT_TAIL%%/*}"
		PROJECT_INDEX_REL="vault/projects/${_PROJECT_SLUG}/index"
		;;
	vault/spaces/*/projects/*/*)
		_SPACE_TAIL="${REL_PATH_NO_EXT#vault/spaces/}"
		_PROJECT_TAIL="${_SPACE_TAIL#*/projects/}"
		_PROJECT_SLUG="${_PROJECT_TAIL%%/*}"
		_SPACE_SLUG="${_SPACE_TAIL%%/*}"
		PROJECT_INDEX_REL="vault/spaces/${_SPACE_SLUG}/projects/${_PROJECT_SLUG}/index"
		;;
esac
if [ -n "$PROJECT_INDEX_REL" ] && [ "$REL_PATH_NO_EXT" != "$PROJECT_INDEX_REL" ] && [ ! -f "$ROOT_DIR/${PROJECT_INDEX_REL}.md" ]; then
	echo "new-note: project '${_PROJECT_SLUG}' has no index.md — create it first with type=project" >&2
	exit 4
fi

# Normalize "macos, linux-arm64" / "macos,linux-arm64" → "[macos, linux-arm64]".
PLATFORM_FIELD=""
if [ -n "$PLATFORM_CSV" ]; then
	NORM="$(echo "$PLATFORM_CSV" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | paste -sd, - | sed 's/,/, /g')"
	PLATFORM_FIELD="platform: [${NORM}]"
fi

ABS_PATH="${ROOT_DIR}/${REL_PATH_NO_EXT}.md"

if [ -e "$ABS_PATH" ]; then
	echo "Refuse to overwrite existing: $ABS_PATH" >&2
	exit 1
fi

mkdir -p "$(dirname "$ABS_PATH")"

UUID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL_PATH_NO_EXT")"
TODAY="$(date -u +%Y-%m-%d)"
# Moment-precisie alleen voor de types waar "wanneer op de dag" ertoe doet
# (loop-records zijn type task; session-notes). UTC, zelfde klok als TODAY.
NOW="$(date -u +%H:%M:%S)"

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
	backlog)   TAGS="[backlog]"   ; SOURCE="source: session" ; STATUS_FIELD="status: todo" ;;
	feedback)  TAGS="[feedback]"  ; SOURCE="source: session" ;;
	reference) TAGS="[reference]" ; SOURCE="" ;;
	session)   TAGS="[session]"   ; SOURCE="" ; EXTRA_FIELDS="time: $NOW" ;;
	device)    TAGS="[device]"    ; SOURCE="" ;;
	integration) TAGS="[integration]" ; SOURCE="" ;;
	spec)      TAGS="[spec]"      ; SOURCE="source: session"
	           STATUS_FIELD="status: draft"
	           EXTRA_FIELDS="version: 1.0.0" ;;
	task)      TAGS="[task]"      ; SOURCE="" ; STATUS_FIELD="status: pending" ; EXTRA_FIELDS="time: $NOW" ;;
	decisions) TAGS="[decisions]" ; SOURCE="" ;;
	explainer) TAGS="[explainer]" ; SOURCE="" ; EXTRA_FIELDS=$'category: general\ntheme: clean-flat' ;;
	space) echo "new-note: space paspoorts have their own scaffold — use: scripts/new-space.sh <slug> --owner \"<name>\" --relation <relation>" >&2; exit 2 ;;
	*) echo "Unknown type: $TYPE (use: learning|project|backlog|feedback|reference|session|device|integration|spec|task|decisions|explainer; for a space use scripts/new-space.sh)" >&2; exit 2 ;;
esac

# Build the work-note MUST body scaffold (system/principles.md #1/#3), locale-aware
# (i18n Fase 2/3). Config decides WHICH sections (contract tier=MUST, location=body);
# the per-locale catalog system/i18n/<locale>/work-note.tsv decides the heading/guide
# STRINGS. Empty when not a work type or config absent (test fixtures), so this stays
# backward-compatible. Values live in config/catalog, never here.
WORK_BODY=""
_wn_contract="$ROOT_DIR/system/work-note-contract.tsv"
_wn_ratchets="$ROOT_DIR/system/ratchets.tsv"
if [ -f "$_wn_contract" ] && [ -f "$_wn_ratchets" ]; then
	_wn_scope="$(awk -F'\t' '!/^#/ && $1=="work-note-contract"{print $3; exit}' "$_wn_ratchets")"
	if [ -n "$_wn_scope" ] && printf '%s' "$TYPE" | grep -qE "^(${_wn_scope})\$"; then
		_wn_locale="en"
		if [ -f "$ROOT_DIR/scripts/lib/locale.sh" ]; then
			# shellcheck source=scripts/lib/locale.sh disable=SC1091
			. "$ROOT_DIR/scripts/lib/locale.sh"
			_wn_locale="$(locale_for "$ABS_PATH" "$ROOT_DIR")"
		fi
		_wn_cat="$ROOT_DIR/system/i18n/${_wn_locale}/work-note.tsv"
		[ -f "$_wn_cat" ] || _wn_cat="$ROOT_DIR/system/i18n/en/work-note.tsv"
		while IFS=$'\t' read -r _k _tier _loc _label _rx; do
			case "$_k" in '' | \#*) continue ;; esac
			[ "$_tier" = "MUST" ] && [ "$_loc" = "body" ] || continue
			_hd=""; _gd=""
			if [ -f "$_wn_cat" ]; then
				_hd="$(awk -F'\t' -v key="$_k" '!/^#/ && $1==key{print $2; exit}' "$_wn_cat")"
				_gd="$(awk -F'\t' -v key="$_k" '!/^#/ && $1==key{print $3; exit}' "$_wn_cat")"
			fi
			[ -n "$_hd" ] || _hd="$_label"
			WORK_BODY="${WORK_BODY}${_hd}"$'\n\n'"<!-- ${_gd} -->"$'\n\n'
		done < "$_wn_contract"
	fi
fi

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
	# Work-note MUST body scaffold, pre-computed above (config + locale driven). Empty
	# when not a work type or config absent, so this stays backward-compatible.
	[ -n "$WORK_BODY" ] && printf '%s' "$WORK_BODY"
} > "$ABS_PATH"

echo "$ABS_PATH"
