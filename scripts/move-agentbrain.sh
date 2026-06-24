#!/usr/bin/env bash
# move-agentbrain.sh — Safely move agentBrain to a new location.
# Updates all pointers, symlinks, env vars, and absolute paths.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $# -lt 1 ]]; then
	echo "Usage: scripts/move-agentbrain.sh <NEW_ABSOLUTE_PATH>"
	echo ""
	echo "Example: scripts/move-agentbrain.sh /Volumes/SSD2/agentBrain"
	exit 1
fi

NEW_VAULT="${1%/}"

if [[ -e "$NEW_VAULT" ]]; then
	echo "ERROR: target already exists: $NEW_VAULT" >&2
	exit 1
fi

if [[ ! -f "${VAULT}/brain.json" ]]; then
	echo "ERROR: brain.json not found at ${VAULT}. Is this agentBrain?" >&2
	exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "agentBrain move"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  From: ${VAULT}"
echo "  To:   ${NEW_VAULT}"
echo ""
read -p "Proceed? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || {
	echo "Aborted."
	exit 0
}

# ── 1. Backup ───────────────────────────────

BACKUP="${VAULT}-backup-$(date +%Y%m%d-%H%M%S)"
echo -e "${YELLOW}Backup${NC}   → ${BACKUP}"
rsync -a "${VAULT}/" "${BACKUP}/"

# ── 2. Move ─────────────────────────────────

echo "Moving..."
mkdir -p "$(dirname "$NEW_VAULT")"
mv "$VAULT" "$NEW_VAULT"

# ── 3. Update paths inside the repo ─────────

echo "Updating internal paths..."
OLD_ESC="$(printf '%s' "$VAULT" | sed 's/[\/&]/\\&/g')"
NEW_ESC="$(printf '%s' "$NEW_VAULT" | sed 's/[\/&]/\\&/g')"

INTERNAL_FILES=(
	"$NEW_VAULT/brain.json"
)
for f in "${INTERNAL_FILES[@]}"; do
	if [[ -f "$f" ]]; then
		sed -i.bak "s|${OLD_ESC}|${NEW_ESC}|g" "$f"
		rm -f "${f}.bak"
	fi
done

# ── 4. Update agent pointers ────────────────

update_pointer() {
	local file="$1"
	if [[ ! -f "$file" ]]; then
		return
	fi
	if grep -q "$VAULT" "$file" 2>/dev/null; then
		sed -i.bak "s|${OLD_ESC}|${NEW_ESC}|g" "$file"
		rm -f "${file}.bak"
		echo -e "${GREEN}Updated${NC}  $(basename "$file")"
	fi
}

# Claude
update_pointer "$HOME/.claude/CLAUDE.md"

# Windsurf
update_pointer "$HOME/.codeium/windsurf/memories/global_rules.md"

# Cline
update_pointer "$HOME/Documents/Cline/Rules/.clinerules"

# Hermes
update_pointer "${HERMES_HOME:-$HOME/.hermes}/SOUL.md"

# Gemini CLI
update_pointer "$HOME/.gemini/GEMINI.md"

# OpenCode
if [[ -f "$HOME/.config/opencode/opencode.json" ]] && grep -q "$VAULT" "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
	python3 -c "
import json
with open('$HOME/.config/opencode/opencode.json') as f:
    cfg = json.load(f)
instructions = cfg.get('instructions', [])
cfg['instructions'] = [i.replace('$VAULT', '$NEW_VAULT') for i in instructions]
with open('$HOME/.config/opencode/opencode.json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null
	echo -e "${GREEN}Updated${NC}  opencode.json"
fi

# Copilot / VS Code settings
if [[ "$(uname)" = "Darwin" ]]; then
	VSCODE_CANDIDATES=(
		"$HOME/Library/Application Support/Code/User/settings.json"
		"$HOME/Library/Application Support/Code - Insiders/User/settings.json"
	)
else
	VSCODE_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
	VSCODE_CANDIDATES=(
		"${VSCODE_BASE}/Code/User/settings.json"
		"${VSCODE_BASE}/Code - Insiders/User/settings.json"
	)
fi
for vsc_settings in "${VSCODE_CANDIDATES[@]}"; do
	update_pointer "$vsc_settings"
done

# ── 5. Update Pi symlinks ───────────────────

echo "Updating Pi symlinks..."
PI_AGENT="$HOME/.pi/agent"
PI_RELINK=(
	"extensions"
	"skills"
	"AGENTS.md"
)
for link_name in "${PI_RELINK[@]}"; do
	link="${PI_AGENT}/${link_name}"
	if [[ -L "$link" ]]; then
		current_target="$(readlink "$link")"
		new_target="${current_target//$VAULT/$NEW_VAULT}"
		if [[ "$current_target" != "$new_target" ]]; then
			ln -sf "$new_target" "$link"
			echo -e "${GREEN}Relinked${NC} ${link_name}"
		fi
	fi
done

# bin/pi is a file, not a dir symlink
PI_BIN="${PI_AGENT}/bin/pi"
if [[ -L "$PI_BIN" ]]; then
	current_target="$(readlink "$PI_BIN")"
	new_target="${current_target//$VAULT/$NEW_VAULT}"
	if [[ "$current_target" != "$new_target" ]]; then
		ln -sf "$new_target" "$PI_BIN"
		echo -e "${GREEN}Relinked${NC} bin/pi"
	fi
fi

# ── 6. Update VAULT env var ─────────────────

SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]] && grep -q "export VAULT=" "$HOME/.zshrc" 2>/dev/null; then
	SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]] && grep -q "export VAULT=" "$HOME/.bashrc" 2>/dev/null; then
	SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
	sed -i.bak "s|export VAULT=.*|export VAULT=\"${NEW_VAULT}\"|g" "$SHELL_RC"
	rm -f "${SHELL_RC}.bak"
	echo -e "${GREEN}Updated${NC}  VAULT in ${SHELL_RC##*/}"
fi

# ── 7. Restore git hooks ────────────────────

if [[ -d "${NEW_VAULT}/.githooks" ]]; then
	git -C "$NEW_VAULT" config core.hooksPath .githooks
	echo -e "${GREEN}Restored${NC} git hooks"
fi

# ── 8. Validate ─────────────────────────────

echo ""
echo "Running doctor..."
VAULT="$NEW_VAULT" bash "${NEW_VAULT}/scripts/doctor.sh" --summary

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Move complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  New location: ${NEW_VAULT}"
echo "  Backup at:    ${BACKUP}"
echo ""
echo "  Next steps:"
echo "    1. Reload your shell: source ${SHELL_RC:-~/.zshrc}"
echo "    2. Restart Pi if it was running"
echo "    3. Delete backup when confirmed: rm -rf ${BACKUP}"
