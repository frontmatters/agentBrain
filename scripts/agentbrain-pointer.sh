#!/usr/bin/env bash
# agentbrain-pointer.sh — Single source for the "read at session start" pointer
# block that each setup-<client>.sh installs into its client config file.
#
# Sourced, not run directly: the list of brain files to read lives in exactly
# one place, so it cannot drift between clients (it used to be copy-pasted per
# client, and some copies silently went thin — missing scopes/skills/config).
# Clients differ only by their per-agent config filename.
#
# Usage (after sourcing):
#   agentbrain_pointer_block "$VAULT" "claude.md" >> "$CLIENT_CONFIG"   # append
#   agentbrain_pointer_block "$VAULT" "cline.md"  >  "$CLIENT_CONFIG"   # overwrite

agentbrain_pointer_block() {
	local vault="$1" agent_config="$2"
	cat <<POINTER

## agentBrain
# Persistent knowledge base at ${vault}
# Read these at session start:
- Patterns: \`${vault}/learnings/patterns.md\`
- Troubleshooting: \`${vault}/learnings/troubleshooting.md\`
- Rules: \`${vault}/system/rules.md\`
- Shared agent config: \`${vault}/system/agent-config/shared.md\`
- Agent config: \`${vault}/system/agent-config/${agent_config}\`
- Skills: \`${vault}/system/skills.md\`
- Brain status (live): \`${vault}/local/sessions/startup-context.md\` — current open findings + alerts (skip if file absent)
- Preferences scopes: read any existing files under \`${vault}/local/preferences/organization/\`, \`${vault}/local/preferences/team/\`, and \`${vault}/local/preferences/personal/\`.

# Self-learning: write insights to the brain during sessions.
# See \`${vault}/system/rules.md\` for the full protocol.

# Writing a note under local/: ALWAYS use \`bash ${vault}/scripts/new-note.sh <type> <vault-relative-path-no-ext> [title]\`
# to get correct frontmatter + computed UUID5. NEVER type the id by hand —
# the brain enforces uuid5-gen.sh parity at write-time (CC PostToolUse hook,
# Pi note-id-validator extension) and will reject mismatches.
POINTER
}
