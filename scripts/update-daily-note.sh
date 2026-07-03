#!/usr/bin/env bash
# update-daily-note.sh — Adds a line to today's daily note.
# Creates the daily note from template if it does not exist yet.
#
# Distinction from ensure-daily-note.sh:
#   ensure-daily-note.sh  — only guarantees the file exists (no content added)
#   update-daily-note.sh  — adds a timestamped entry and creates file if missing
#
# Usage:
#   ./update-daily-note.sh "Short description of what was done"
#   ./update-daily-note.sh --section notes "A standalone note"
#
# Sections: sessions (default), notes, links

set -euo pipefail

# Detect vault root (parent of scripts/)
VAULT="$(cd "$(dirname "$0")/.." && pwd)"
DAILY_DIR="${VAULT}/daily-notes"
TEMPLATE="${VAULT}/templates/daily.md"
TODAY=$(date '+%Y-%m-%d')
DAILY_FILE="${DAILY_DIR}/${TODAY}.md"

# Parse arguments
SECTION="Sessions"
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--section | -s)
		case "${2,,}" in
		sessions | session) SECTION="Sessions" ;;
		notes | note) SECTION="Notes" ;;
		links | link) SECTION="Links" ;;
		*) SECTION="$2" ;;
		esac
		shift 2
		;;
	*)
		DESCRIPTION="$1"
		shift
		;;
	esac
done

if [ -z "$DESCRIPTION" ]; then
	echo "Usage: $(basename "$0") [-s section] \"description\""
	echo "Sections: sessions (default), notes, links"
	exit 1
fi

# Create daily-notes directory if it does not exist
mkdir -p "$DAILY_DIR"

# Create daily note from template if it does not exist
if [ ! -f "$DAILY_FILE" ]; then
	if [ -f "$TEMPLATE" ]; then
		sed "s/{{date}}/${TODAY}/g" "$TEMPLATE" >"$DAILY_FILE"
		echo "Daily note created: ${DAILY_FILE}"
	else
		cat >"$DAILY_FILE" <<TMPL
---
date: ${TODAY}
type: daily
tags: [daily]
---

# ${TODAY}

## Sessions
-

## Notes
-

## Links
-
TMPL
		echo "Daily note created (without template): ${DAILY_FILE}"
	fi
fi

# Find the section and add the line
SECTION_HEADER="## ${SECTION}"

if grep -q "^${SECTION_HEADER}$" "$DAILY_FILE"; then
	awk -v section="$SECTION_HEADER" -v line="- ${DESCRIPTION}" '
    BEGIN { in_section = 0; added = 0 }
    /^## / {
      if (in_section && !added) {
        print line
        added = 1
      }
      in_section = ($0 == section) ? 1 : 0
    }
    { print }
    END {
      if (in_section && !added) {
        print line
      }
    }
  ' "$DAILY_FILE" >"${DAILY_FILE}.tmp" && mv "${DAILY_FILE}.tmp" "$DAILY_FILE"
else
	{
		echo ""
		echo "${SECTION_HEADER}"
		echo "- ${DESCRIPTION}"
	} >>"$DAILY_FILE"
fi

echo "Added to ${SECTION}: ${DESCRIPTION}"
