#!/usr/bin/env bash
# check-client-pointers.sh — Validate cross-client agentBrain pointer consistency.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failures=$((failures + 1))
}

require_pattern() {
	local file="$1" pattern="$2" desc="$3"
	[[ -f "$file" ]] || {
		fail "$desc: missing file $file"
		return
	}
	grep -Eq "$pattern" "$file" || fail "$desc: pattern '$pattern' missing in $file"
}

client_configs=(
	system/agent-config/shared.md
	system/agent-config/claude.md
	system/agent-config/copilot.md
	system/agent-config/windsurf.md
	system/agent-config/gemini.md
)

for file in "${client_configs[@]}"; do
	require_pattern "$file" 'local/preferences/organization/' "organization preference scope in $file"
	require_pattern "$file" 'local/preferences/team/' "team preference scope in $file"
	require_pattern "$file" 'local/preferences/personal/' "personal preference scope in $file"
done

for file in system/agent-config/claude.md system/agent-config/copilot.md system/agent-config/windsurf.md system/agent-config/gemini.md; do
	require_pattern "$file" 'local/daily-notes' "daily note pointer in $file"
done

# The session-start pointer block now lives in one shared source
# (agentbrain-pointer.sh), sourced by every setup-<client>.sh that setup.sh runs.
# Validate the scopes + per-agent config reference there — one place, not N copies.
require_pattern scripts/agentbrain-pointer.sh 'local/preferences/organization/' 'pointer block organization scope'
require_pattern scripts/agentbrain-pointer.sh 'local/preferences/team/' 'pointer block team scope'
require_pattern scripts/agentbrain-pointer.sh 'local/preferences/personal/' 'pointer block personal scope'
require_pattern scripts/agentbrain-pointer.sh 'system/agent-config/' 'pointer block references per-agent config'
require_pattern scripts/setup-claude-code.sh 'agentbrain_pointer_block' 'setup-claude-code uses the shared pointer block'
require_pattern scripts/setup-gemini-cli.sh 'GEMINI\.md' 'setup-gemini-cli writes GEMINI.md'
require_pattern scripts/setup-gemini-cli.sh 'gemini.md' 'setup-gemini-cli passes its agent-config'

# Copilot entrypoint should route to shared/copilot config and mention daily note context.
require_pattern .github/copilot-instructions.md 'system/agent-config/shared.md' 'Copilot shared config pointer'
require_pattern .github/copilot-instructions.md 'system/agent-config/copilot.md' 'Copilot-specific config pointer'
require_pattern .github/copilot-instructions.md 'daily note' 'Copilot daily note instruction'

# Avoid reintroducing legacy flat preference pointer as the primary documented target.
if grep -R 'Preferences:.*local/preferences/`\|Preferences:.*local/preferences/$' system/agent-config scripts/setup.sh .github/copilot-instructions.md 2>/dev/null; then
	fail 'legacy flat Preferences pointer remains in client config/setup'
fi

if [[ "$failures" -gt 0 ]]; then
	printf 'Client pointer check failed (%d issue(s)).\n' "$failures" >&2
	exit 1
fi

printf 'Client pointer check passed.\n'
