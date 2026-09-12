#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# brain-explain onboarding: first-run theme setup. Idempotent (detect-before-ask):
# if a personal default theme is already configured it is a no-op. Detects whether
# an LLM backend is reachable; if so it points at `theme new`, otherwise it falls
# back to the guided copy-clean-flat template. Never a dead-end prompt.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_THEMES="${EXPLAINERS_LOCAL_THEMES:-$ROOT/vault/explainers/themes}"
CFG="${EXPLAINERS_CONFIG:-$ROOT/vault/explainers/config.json}"

# Detect-before-ask: a personal default already set is a no-op.
if [ -f "$CFG" ] && grep -q '"default_theme"' "$CFG"; then
	echo "brain-explain: a default theme is already configured ($CFG). Nothing to do."
	exit 0
fi

llm_reachable() {
	[ "${BRAIN_EXPLAIN_NO_LLM:-0}" = "1" ] && return 1
	command -v ollama >/dev/null 2>&1 && ollama list >/dev/null 2>&1 && return 0
	return 1
}

echo "brain-explain onboarding: pick how your explainers look."
if llm_reachable; then
	echo "An LLM backend is reachable. Describe your style and I'll build a theme:"
	echo "    bash $HERE/bin/brain-explain theme new <name> --prompt \"<your style>\""
else
	echo "No LLM backend reachable. Start from a shipped theme:"
	echo "    editorial (default) · whiteboard · clean-flat"
	echo "  To make it your own: cp -r '$ROOT/system/explainers/themes/clean-flat' '$LOCAL_THEMES/mine' and edit,"
	echo "  then set { \"default_theme\": \"mine\" } in $CFG."
fi
exit 0
