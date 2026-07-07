#!/usr/bin/env bash
# validate-note-id.sh — validate that a brain note's `id:` field matches uuid5-gen.sh
# for its vault-relative path. Used by:
#   - Claude Code PostToolUse hook (per ~/.claude/settings.json)
#   - Pi extension tool_result hook (per system/pi-config/extensions/agentbrain.ts)
#   - Future agent integrations
#
# Usage:
#   bash scripts/validate-note-id.sh <file-path>
#
# Exit codes:
#   0 — valid (or not-applicable: not under local/, not a .md, no frontmatter, no id field)
#   1 — id mismatch (with diagnostic message on stderr)
#   2 — usage error

set -euo pipefail

# Resolve an absolute path lexically — WITHOUT requiring the target to exist.
# bash `pwd` is logical (keeps symlinks like ~/agentBrain), so the brain-root
# walk-up below still finds brain.json via the alias. This lets --content-file
# validate a note BEFORE it's written (its dir may not exist yet).
resolve_abs() {
	case "$1" in
		/*) printf '%s\n' "$1" ;;
		*)  printf '%s\n' "$(pwd)/$1" ;;
	esac
}

# Args: <file-path> [--content-file <candidate>]
#   --content-file: read the `id:` from <candidate> and validate it AS IF written
#   to <file-path>. Used by the Pi pre-write (tool_call) guard. Without it, the id
#   is read from <file-path> itself (post-write hook + commit-time gate).
FILE=""
CONTENT_FILE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--content-file) CONTENT_FILE="${2:-}"; shift 2 ;;
		--content-file=*) CONTENT_FILE="${1#--content-file=}"; shift ;;
		-*) echo "Usage: $0 <file-path> [--content-file <path>]" >&2; exit 2 ;;
		*)
			if [ -z "$FILE" ]; then FILE="$1"; shift
			else echo "Usage: $0 <file-path> [--content-file <path>]" >&2; exit 2; fi ;;
	esac
done
[ -n "$FILE" ] || { echo "Usage: $0 <file-path> [--content-file <path>]" >&2; exit 2; }

# Where the id is read from, and existence semantics, differ per mode.
if [ -n "$CONTENT_FILE" ]; then
	[ -f "$CONTENT_FILE" ] || exit 0   # nothing to validate
	ID_SRC="$CONTENT_FILE"
else
	[ -f "$FILE" ] || exit 0            # file gone? not our problem
	ID_SRC="$FILE"
fi

# Only validate .md targets
[[ "$FILE" == *.md ]] || exit 0

# Resolve absolute path of the TARGET (works even if it doesn't exist yet)
ABS_FILE="$(resolve_abs "$FILE")"

# Find the brain root: walk up until we see brain.json
BRAIN_ROOT=""
DIR="$(dirname "$ABS_FILE")"
while [ "$DIR" != "/" ]; do
	if [ -f "$DIR/brain.json" ]; then
		BRAIN_ROOT="$DIR"
		break
	fi
	DIR="$(dirname "$DIR")"
done

# Not in a brain? not our concern
[ -n "$BRAIN_ROOT" ] || exit 0

# Compute vault-relative path (no .md). Quote pattern to satisfy shellcheck SC2295.
REL="${ABS_FILE#"${BRAIN_ROOT}"/}"
REL_NO_EXT="${REL%.md}"

# Only validate notes under local/ — system/learnings/ have their own schemas
[[ "$REL" == local/* ]] || exit 0

# Skip machine-generated paths (same exempts as check-local-content.sh).
# These use their own id strategy (content-hash) or have no path-derived id, so a
# path-uuid5 check is a false positive — keep this list in sync with check-local-content.sh.
case "$REL" in
	local/skills/*/SKILL.md|local/addons/*/SKILL.md|local/addons/*/manifest.md) exit 0 ;;
	local/quarantine/*|local/sessions/session-journal.md|local/sessions/archive/*|local/sessions/README.md) exit 0 ;;
	local/sessions/startup-context.md|local/findings/*|local/metrics/*|local/logs/*) exit 0 ;;
	local/learnings/extracted/*|local/youtube-digest/*) exit 0 ;;
	local/backlog/auto-findings-triage.md|local/analyses/*) exit 0 ;;
esac

# Extract `id:` field from frontmatter (first 20 lines, lazy match) — from the
# id-source (the on-disk file, or the candidate content in --content-file mode).
ID_ACTUAL="$(awk 'NR>20{exit} /^id:[[:space:]]/{sub(/^id:[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); print; exit}' "$ID_SRC")"

# No id field? not our concern (some notes legitimately have none)
[ -n "$ID_ACTUAL" ] || exit 0

# Compute expected id
ID_EXPECTED="$(bash "$BRAIN_ROOT/scripts/uuid5-gen.sh" "$REL_NO_EXT")"

if [ "$ID_ACTUAL" != "$ID_EXPECTED" ]; then
	cat >&2 <<EOF
validate-note-id: ID MISMATCH in $REL
  actual:   $ID_ACTUAL
  expected: $ID_EXPECTED
Fix: replace id field with the expected value. Or recompute via:
  bash scripts/uuid5-gen.sh "$REL_NO_EXT"
EOF
	exit 1
fi
