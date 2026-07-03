#!/usr/bin/env bash
# install-agent-clis.sh — Optionally install/uninstall AI agent CLIs (opt-in, agent-agnostic).
#
# Checkbox menu: ↑/↓ move, Space marks the highlighted row, Enter applies, q cancels.
# Marking depends on the row's current state:
#   - a MISSING agent  → marked for INSTALL   ([+], green)
#   - an INSTALLED one → marked for UNINSTALL  ([✗], red, name struck through)
# A standalone module; also called by setup.sh. Skips entirely non-interactively — agentBrain
# connects to whatever agents you have; (un)installing them is a convenience, never a default.
#
# Portable (macOS, Linux, WSL; bash 3.2+): arrow keys send ESC [ A/B (3 bytes together); read
# the 2 trailing bytes WITHOUT a `-t` timeout (bash 3.2 — Apple's default — rejects a fractional
# one). Strikethrough uses a Unicode overlay, not ANSI SGR 9 (which macOS Terminal.app ignores).
# Static header + in-place list redraw avoid flicker. Every install command here is npm/`code`.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Strike text through, terminal-independent: append a Unicode combining long stroke overlay
# (U+0336 = UTF-8 0xCC 0xB6) after each character. Real struck-through glyphs, so it shows even
# where ANSI strikethrough (SGR 9) doesn't render (e.g. macOS Terminal.app). Names are ASCII.
strike() {
	local s="$1" out="" combine=$'\xcc\xb6' c
	for ((c = 0; c < ${#s}; c++)); do out="${out}${s:c:1}${combine}"; done
	printf '%s' "$out"
}

# id | display | install command | detect command (empty = no command-line check).
# Only CLIs/extensions with a portable install (npm, `code`) — GUI apps like Cursor/Windsurf
# are installed by the user (platform-specific), not via this menu. So every command here works
# on macOS, Linux and WSL. agentBrain is agent-agnostic; Pi is listed first + flagged
# recommended only because it has the deepest integration today (informational, not a default).
AGENTS=(
	"pi|Pi|npm install -g @earendil-works/pi-coding-agent|pi"
	"claude-code|Claude Code|npm install -g @anthropic-ai/claude-code|claude"
	"copilot|GitHub Copilot CLI|npm install -g @github/copilot|copilot"
	"gemini-cli|Gemini CLI|npm install -g @google/gemini-cli|gemini"
	"opencode|OpenCode|npm install -g opencode-ai|opencode"
	"vscode-copilot|VS Code Copilot extension|code --install-extension GitHub.copilot|"
	"cline|Cline (VS Code extension)|code --install-extension saoudrizwan.claude-dev|"
)
N=${#AGENTS[@]}

# Never (un)install an agent non-interactively.
if [ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
	echo "Agent CLI install: skipped (non-interactive — agentBrain connects to agents you install yourself)."
	exit 0
fi

declare -a MARK
for ((i = 0; i < N; i++)); do MARK[i]=0; done
cursor=0

# Detect-status cache (1 = installed). Determines whether a mark means uninstall or install.
declare -a INSTALLED
for ((i = 0; i < N; i++)); do
	IFS='|' read -r _ _ _ detect <<<"${AGENTS[$i]}"
	if [ -n "$detect" ] && command -v "$detect" &>/dev/null; then INSTALLED[i]=1; else INSTALLED[i]=0; fi
done

echo -e "${CYAN}Install / uninstall agent CLIs${NC} — optional"
echo "agentBrain connects to whatever you have; this is a convenience. Pi is recommended"
echo "(deepest integration today). Space marks a row: a missing agent → install, an installed"
echo -e "one → ${RED}uninstall${NC} (struck through)."
echo
echo "↑/↓ move · Space mark · a = mark all · Enter = apply · q = cancel"
echo

LIST_LINES=$((N + 2)) # N rows + blank + summary
first_render=1

render() {
	[ "$first_render" -eq 1 ] && first_render=0 || printf '\033[%dA' "$LIST_LINES"
	printf '\033[J'
	local ins=0 uns=0
	for ((i = 0; i < N; i++)); do
		IFS='|' read -r id name _ _ <<<"${AGENTS[$i]}"
		local pointer="  "
		[ "$i" -eq "$cursor" ] && pointer="${CYAN}>${NC} "
		local inst=""
		[ "${INSTALLED[i]}" -eq 1 ] && inst=" (installed)"
		local rec=""
		[ "$id" = "pi" ] && rec=" ${CYAN}(recommended)${NC}"
		local box="[ ]" label=""
		if [ "${MARK[i]}" -eq 1 ] && [ "${INSTALLED[i]}" -eq 1 ]; then
			# Uninstall: strike the NAME (+installed), keep the box as the marker.
			box="[${RED}✗${NC}]"
			label="${RED}$(strike "${name}${inst}")${NC}"
			uns=$((uns + 1))
		elif [ "${MARK[i]}" -eq 1 ]; then
			box="[${GREEN}+${NC}]"
			label="${name}"
			ins=$((ins + 1))
		else
			label="${name}${YELLOW}${inst}${NC}"
		fi
		printf "%b%b %b%b\n" "$pointer" "$box" "$label" "$rec"
	done
	echo ""
	printf "%d to install · %d to uninstall\n" "$ins" "$uns"
}

while true; do
	render
	IFS= read -rsn1 key || break
	case "$key" in
	$'\x1b')
		IFS= read -rsn2 -r rest 2>/dev/null || rest=""
		case "$rest" in
		'[A' | 'OA') cursor=$(((cursor - 1 + N) % N)) ;;
		'[B' | 'OB') cursor=$(((cursor + 1) % N)) ;;
		esac
		;;
	' ') MARK[cursor]=$((1 - MARK[cursor])) ;;
	a | A) for ((i = 0; i < N; i++)); do MARK[i]=1; done ;;
	q | Q)
		echo ""
		echo "Cancelled — nothing changed."
		exit 0
		;;
	'') break ;; # Enter → apply
	esac
done

# Apply: install missing marked agents, uninstall installed marked ones.
todo=()
for ((i = 0; i < N; i++)); do [ "${MARK[i]}" -eq 1 ] && todo+=("$i"); done
if [ "${#todo[@]}" -eq 0 ]; then
	echo ""
	echo "Nothing marked — no changes."
	exit 0
fi

echo ""
ok=0
fail=0
for i in "${todo[@]}"; do
	IFS='|' read -r _ name cmd _ <<<"${AGENTS[$i]}"
	if [ "${INSTALLED[i]}" -eq 1 ]; then
		action="Uninstalling"
		# Derive the uninstall command: every install verb here contains "install"
		# (npm install / brew install --cask / code --install-extension).
		run="${cmd//install/uninstall}"
	else
		action="Installing"
		run="$cmd"
	fi
	echo -e "${CYAN}${action} ${name}${NC} — ${run}"
	# Show real output: a wrong/rotted command must fail visibly, never a silent success.
	if eval "$run"; then
		echo -e "  ${GREEN}✓${NC} ${name}"
		ok=$((ok + 1))
	else
		echo -e "  ${RED}✗${NC} ${name} failed — run manually: ${run}"
		fail=$((fail + 1))
	fi
done

echo ""
echo "Done: ${ok} ok, ${fail} failed. (Re-run setup so agentBrain reflects the change.)"
