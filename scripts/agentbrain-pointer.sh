#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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

# agentbrain_pointer_target_ok <client-config-file> <checkout>
# A client config that resolves into the agentBrain checkout or its vault is a
# symlink into a git-tracked file: appending the pointer there edits the product
# (or a vault note) instead of the client config, and the privacy scan then flags
# the absolute paths it carries. Refuse, and say which link to replace.
agentbrain_pointer_target_ok() {
	local target="$1" checkout="$2" resolved root
	resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target" 2>/dev/null)" || return 0
	for root in "$checkout" "$checkout/vault"; do
		root="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root" 2>/dev/null)" || continue
		case "$resolved/" in "$root"/*)
			echo "agentBrain: not writing the pointer into $target: it resolves to $resolved, inside $root." >&2
			echo "  Replace that symlink with a regular file, then re-run setup." >&2
			return 1 ;;
		esac
	done
	return 0
}

agentbrain_pointer_block() {
	local vault="$1" agent_config="$2"
	cat <<POINTER

## agentBrain
# Persistent knowledge base at ${vault}
# Path contract: ${vault} is the checkout root (AGENTBRAIN_DIR).
# Private knowledge is mounted below it at ${vault}/vault (VAULT_DIR), often
# as a symlink to an external directory. Never address private files directly
# below the checkout root (for example <checkout>/learnings); use
# ${vault}/vault/<area>.
# If a tool needs an absolute path, verify the resolved mount first with
# \`realpath ${vault}/vault\` rather than inferring it from the checkout name.
# Read these at session start:
- Patterns: \`${vault}/vault/learnings/patterns.md\`
- Troubleshooting: \`${vault}/vault/learnings/troubleshooting.md\`
- Rules: \`${vault}/system/rules.md\`
- Shared agent config: \`${vault}/system/agent-config/shared.md\`
- Agent config: \`${vault}/system/agent-config/${agent_config}\`
- Skills: \`${vault}/system/skills.md\`
- Brain status (live): \`${vault}/vault/sessions/startup-context.md\` — current open findings + alerts (skip if file absent)
- Preferences scopes: read any existing files under \`${vault}/vault/preferences/organization/\`, \`${vault}/vault/preferences/team/\`, and \`${vault}/vault/preferences/personal/\`.

# Self-learning: write insights to the brain during sessions.
# See \`${vault}/system/rules.md\` for the full protocol.

# Writing a note under vault/: ALWAYS use \`bash ${vault}/scripts/new-note.sh <type> <vault-relative-path-no-ext> [title]\`
# to get correct frontmatter + computed UUID5. NEVER type the id by hand —
# the brain enforces uuid5-gen.sh parity at write-time (CC PostToolUse hook,
# Pi note-id-validator extension) and will reject mismatches.
POINTER
}
