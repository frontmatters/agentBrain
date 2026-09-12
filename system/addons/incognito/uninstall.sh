#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Uninstall the incognito addon: clear any active flag so the vault is writable
# again. Does NOT touch settings.json (remove the PreToolUse entry by hand if you
# registered it). Never destructive beyond the flag file.
set -euo pipefail
VAULT="${AGENTBRAIN_HOME:-$HOME}/agentBrain"
FLAG="$VAULT/vault/sessions/.incognito"

if [ -f "$FLAG" ]; then
	rm -f "$FLAG"
	echo "✓ cleared active incognito flag ($FLAG)"
else
	echo "• no active incognito flag"
fi

echo "ℹ️  if you wired the PreToolUse guard into ~/.claude/settings.json, remove it manually:"
echo "    incognito/claude-pretooluse-guard.sh"
