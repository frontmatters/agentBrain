#!/usr/bin/env bash
# setup-structure.sh — Create agentBrain directory structure.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Shared directories (tracked in git)
DIRS=("learnings" "projects" "sessions" "daily-notes" "user-preferences" "templates" "system" "scripts")
for dir in "${DIRS[@]}"; do
	if [ ! -d "${VAULT}/${dir}" ]; then
		mkdir -p "${VAULT}/${dir}"
		echo -e "${GREEN}Created${NC} ${dir}/"
	fi
done

# Personal directories (gitignored)
LOCAL_DIRS=(
	"local/projects"
	"local/sessions"
	"local/daily-notes"
	"local/memories"
	"local/integrations"
	"local/learnings"
	"local/learnings/extracted"
	"local/skills"
	"local/preferences"
	"local/preferences/personal"
	"local/research"
	"local/reports"
	"local/security"
	"local/setup-history"
	"local/youtube-digest"
	"local/backlog"
)
for dir in "${LOCAL_DIRS[@]}"; do
	if [ ! -d "${VAULT}/${dir}" ]; then
		mkdir -p "${VAULT}/${dir}"
		echo -e "${GREEN}Created${NC} ${dir}/"
	fi
done

KEEPDIRS=("sessions" "daily-notes" "projects")
for dir in "${KEEPDIRS[@]}"; do
	if [ ! -f "${VAULT}/${dir}/.gitkeep" ]; then
		touch "${VAULT}/${dir}/.gitkeep"
		echo -e "${GREEN}Created${NC} ${dir}/.gitkeep"
	fi
done
