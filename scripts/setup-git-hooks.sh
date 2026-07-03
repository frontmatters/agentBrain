#!/usr/bin/env bash
# setup-git-hooks.sh — Configure git pre-commit hooks.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -d "${VAULT}/.githooks" ]; then
	if ! git -C "${VAULT}" rev-parse --git-dir >/dev/null 2>&1; then
		# Release/zip install (not a git checkout) — nothing to wire, don't abort setup.
		echo -e "${YELLOW}Skip${NC}    git hooks (not a git checkout)"
	else
		CURRENT_HOOKS=$(git -C "${VAULT}" config core.hooksPath 2>/dev/null || echo "")
		if [ "$CURRENT_HOOKS" = ".githooks" ]; then
			echo -e "${YELLOW}Exists${NC}  git hooks already active (.githooks)"
		else
			git -C "${VAULT}" config core.hooksPath .githooks
			echo -e "${GREEN}Enabled${NC} git pre-commit privacy hook (.githooks)"
		fi
	fi
fi
