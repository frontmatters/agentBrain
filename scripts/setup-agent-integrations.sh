#!/usr/bin/env bash
# setup-agent-integrations.sh — Install agentBrain pointers for all detected AI clients.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Each client gets a global config entry that points to this brain.
# Safe to re-run (idempotent).
#
# Called by: scripts/setup.sh
# Can also be run standalone to add or refresh integrations.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPTS="${VAULT}/scripts"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

export VAULT

# List of available agent integrations
# Format: "script_name:agent_name:check_command"
AGENTS=(
	"setup-claude-code.sh:Claude Code:claude"
	"setup-copilot.sh:Copilot:code"
	"setup-copilot-cli.sh:Copilot CLI:copilot"
	"setup-windsurf.sh:Windsurf:windsurf"
	"setup-cursor.sh:Cursor:cursor"
	"setup-cline.sh:Cline:cline"
	"setup-opencode.sh:OpenCode:opencode"
	"setup-gemini-cli.sh:Gemini CLI:gemini"
	"setup-hermes.sh:Hermes:hermes"
)

SKIPPED_NAMES=()

for agent_config in "${AGENTS[@]}"; do
	IFS=':' read -r script agent_name check_command <<<"$agent_config"
	script_path="${SCRIPTS}/${script}"
	[ -f "$script_path" ] || continue

	# CLI absent → group it without running. (When there's no check command, run anyway;
	# the script self-detects.)
	if [ -n "$check_command" ] && ! command -v "$check_command" &>/dev/null; then
		SKIPPED_NAMES+=("$agent_name")
		continue
	fi

	# Run it: the script prints its own ✓ / guidance / already-configured on success, or
	# exits non-zero (e.g. exit 2 = its config dir is absent) → group that skip too.
	bash "$script_path" || SKIPPED_NAMES+=("$agent_name")
done

if [ "${#SKIPPED_NAMES[@]}" -gt 0 ]; then
	skipped_list="$(printf '%s, ' "${SKIPPED_NAMES[@]}")"
	echo -e "  ${YELLOW}–${NC} ${#SKIPPED_NAMES[@]} not installed, skipped: ${skipped_list%, }"
fi

# Skills — install the brain's skills (public + personal) into each agent's native dir,
# so every agent gets the same skills, not just the text index.
bash "${SCRIPTS}/setup-skills.sh"

# Daily note — delegate to the single source so there is no second template
# to drift from ensure-daily-note.sh.
bash "${SCRIPTS}/ensure-daily-note.sh"
