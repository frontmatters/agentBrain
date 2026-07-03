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

if [ $# -ne 1 ]; then
	echo "Usage: $0 <file-path>" >&2
	exit 2
fi

FILE="$1"
[ -f "$FILE" ] || exit 0  # file gone? not our problem

# Only validate .md files
[[ "$FILE" == *.md ]] || exit 0

# Resolve absolute path so we can check if it's under a brain root
ABS_FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

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

# Extract `id:` field from frontmatter (first 20 lines, lazy match)
ID_ACTUAL="$(awk 'NR>20{exit} /^id:[[:space:]]/{sub(/^id:[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); print; exit}' "$FILE")"

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
