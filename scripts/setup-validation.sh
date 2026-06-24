#!/usr/bin/env bash
# setup-validation.sh — Validate agentBrain setup and show summary.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Shows counts of learnings, projects, skills, and templates.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
TEMPLATES=("learning.md" "project.md" "session.md" "daily.md")
MISSING=0
for tmpl in "${TEMPLATES[@]}"; do
	[ ! -f "${VAULT}/templates/${tmpl}" ] && MISSING=$((MISSING + 1))
done

# Count the user's real knowledge (local/), not public placeholders/templates. Exclude
# READMEs and anything under an _example/ (or other _*) template dir — find recurses into
# such dirs, so a name filter alone would count the example project's files.
count_notes() {
	find "$1" -type f -name "*.md" ! -name "README.md" ! -name "_*" -not -path '*/_*/*' 2>/dev/null | wc -l | tr -d ' '
}
LEARNINGS=$(count_notes "${VAULT}/local/learnings")
LOCAL_PROJECTS=$(count_notes "${VAULT}/local/projects")
SKILLS=$(find "${VAULT}/system/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')

echo "─────────────────────────────────────────"
echo "  Learnings:  ${LEARNINGS} notes"
echo "  Projects:   ${LOCAL_PROJECTS} notes"
echo "  Skills:     ${SKILLS} available"
echo "  Templates:  $((${#TEMPLATES[@]} - MISSING))/${#TEMPLATES[@]} present"
echo "─────────────────────────────────────────"

# Check for placeholder preference files
PLACEHOLDER_COUNT=0
for pref in "${VAULT}/local/preferences/personal"/*.md; do
	[ -f "$pref" ] && grep -q "This is an example file" "$pref" 2>/dev/null && PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + 1))
done

# Return exit code based on validation status
if [ $MISSING -gt 0 ]; then
	exit 1
fi
