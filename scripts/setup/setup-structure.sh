#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-structure.sh — Create agentBrain directory structure.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Shared directories (tracked in git)

# Personal directories (gitignored)
# The vault is vault/, a symlink that setup-local-vault.sh points outside the
# checkout. This script never creates a vault directory here: a vault inside a
# checkout is exactly what the layout forbids.
if [ ! -L "${VAULT}/vault" ]; then
	echo -e "${YELLOW}!${NC} ${VAULT}/vault is not a symlink; run scripts/setup/setup-local-vault.sh first." >&2
	exit 1
fi
LOCAL_DIRS=(
	"vault/projects"
	"vault/sessions"
	"vault/daily-notes"
	"vault/memories"
	"vault/integrations"
	"vault/learnings"
	"vault/learnings/extracted"
	"vault/skills"
	"vault/preferences"
	"vault/preferences/personal"
	"vault/research"
	"vault/reports"
	"vault/security"
	"vault/setup-history"
	"vault/youtube-digest"
	"vault/backlog"
)
for dir in "${LOCAL_DIRS[@]}"; do
	if [ ! -d "${VAULT}/${dir}" ]; then
		mkdir -p "${VAULT}/${dir}"
		echo -e "${GREEN}Created${NC} ${dir}/"
	fi
done

