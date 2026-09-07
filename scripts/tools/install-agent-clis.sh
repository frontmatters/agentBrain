#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# install-agent-clis.sh — Optionally install/uninstall AI agent CLIs and tools (opt-in, agent-agnostic).
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

# Is npm's global module dir (or its nearest existing ancestor) writable by us? `npm install -g`
# lands in `$(npm config get prefix)/lib/node_modules`; a root-owned prefix (system Node's
# /usr/lib) is exactly what makes it die with EACCES. Testing the nearest existing ancestor lets
# a not-yet-created nvm prefix dir (writable parent) still count as OK, avoiding false blocks.
npm_global_writable() {
	command -v npm >/dev/null 2>&1 || return 0 # no npm → let the real command report it
	local d
	d="$(npm config get prefix 2>/dev/null)/lib/node_modules"
	while [ -n "$d" ] && [ ! -e "$d" ]; do d="${d%/*}"; done
	[ -n "$d" ] && [ -w "$d" ] && return 0
	return 1
}

# id | display | install command | detect command (empty = no command-line check).
# Only CLIs/extensions with a portable install (npm, `code`) — GUI apps like Cursor/Windsurf
# are installed by the user (platform-specific), not via this menu. So every command here works
# on macOS, Linux and WSL. agentBrain is agent-agnostic; Pi is listed first + flagged
# recommended only because it has the deepest integration today (informational, not a default).
AGENTS=(
	# agentBrain Harness belongs to agentBrain and is offered first.
	"abh|agentBrain Harness|npm install -g @agentbrain-harness/abh|abh"
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

# The shared prompt helper decodes terminal bytes into semantic keys (UP/DOWN/etc.).
# shellcheck disable=SC1091
. "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)/installer/prompt-helper.sh"

# Prefer user-scoped nvm Node/npm over any system Node, so the `npm install -g` commands below
# target a user-writable global prefix (~/.nvm/...) instead of a root-only one (system Node's
# /usr/lib, which fails with EACCES). Sourced best-effort; a missing/odd nvm never aborts the
# menu. Also makes the install-detection below see nvm-managed CLIs on PATH.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true

declare -a MARK
for ((i = 0; i < N; i++)); do MARK[i]=0; done
cursor=0

# Detect-status cache (1 = installed). A PATH entry alone is not enough: a stale
# shim or config directory must not make a clean machine look like it has an agent.
declare -a INSTALLED VERSIONS LATEST
for ((i = 0; i < N; i++)); do
	IFS='|' read -r id _ _ detect <<<"${AGENTS[$i]}"
	VERSIONS[i]=""
	LATEST[i]=""
	if [ -n "$detect" ] && command -v "$detect" &>/dev/null; then
		version="$($detect --version </dev/null 2>/dev/null | head -1 | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-28)" || version=""
		if [ -n "$version" ]; then
			INSTALLED[i]=1; VERSIONS[i]="$version"
			if [ "$id" = "abh" ] && command -v npm >/dev/null 2>&1; then
				LATEST[i]="$(npm view @agentbrain-harness/abh version 2>/dev/null | head -1 | tr -d '[:space:]')" || LATEST[i]=""
			fi
		else INSTALLED[i]=0; fi
	else
		INSTALLED[i]=0
	fi
done

echo -e "${CYAN}Install / uninstall agent CLIs and tools${NC} — optional"
echo "agentBrain connects to whatever you have; this is a convenience. agentBrain Harness and Pi are recommended"
echo "(deepest integrations today). Space marks a row: a missing agent → install, an installed"
echo -e "one → ${RED}uninstall${NC} (struck through)."
echo
echo "↑/↓ or number move · Space/number toggle · a = all · Enter = apply · q = cancel"
echo

# Redraw only our own block, in place — exactly like the shared prompt helper.
# Never clear the viewport: earlier questions and the prerequisites scan stay
# visible above the menu. Every frame prints exactly CLI_LIST_LINES lines.
CLI_LIST_LINES=0
render() {
	if [ "$CLI_LIST_LINES" -gt 0 ]; then printf '\033[%sA' "$CLI_LIST_LINES"; fi
	local ins=0 uns=0
	for ((i = 0; i < N; i++)); do
		IFS='|' read -r id name _ _ <<<"${AGENTS[$i]}"
		local pointer="  "
		[ "$i" -eq "$cursor" ] && pointer="${CYAN}>${NC} "
		local inst=""
		if [ "${INSTALLED[i]}" -eq 1 ]; then
			inst=" (installed${VERSIONS[i]:+ v${VERSIONS[i]}})"
			if [ "$id" = "abh" ] && [ -n "${LATEST[i]}" ]; then
				# Keep the row below a normal terminal width so the ANSI redraw cursor
				# cannot land in the middle of a wrapped line when Space is pressed.
				installed_short="${VERSIONS[i]#0.1.0-}"
				latest_short="${LATEST[i]#0.1.0-}"
				if [ "${VERSIONS[i]}" = "${LATEST[i]}" ]; then inst=" (${installed_short}, up to date)"; else inst=" (${installed_short} -> ${latest_short}, update)"; fi
			fi
		fi
		local rec=""
		if [ "$id" = "abh" ] || [ "$id" = "pi" ]; then rec=" ${CYAN}(recommended)${NC}"; fi
		local box="[ ]" label=""
		if [ "${MARK[i]}" -eq 1 ] && [ "${INSTALLED[i]}" -eq 1 ] && [ "$id" = "abh" ]; then
			# Update agentBrain Harness in place; it is never removed by this menu.
			box="[${CYAN}↑${NC}]"
			label="${CYAN}${name}${inst}${NC}"
			ins=$((ins + 1))
		elif [ "${MARK[i]}" -eq 1 ] && [ "${INSTALLED[i]}" -eq 1 ]; then
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
		printf "\033[2K%b%b %b%b\n" "$pointer" "$box" "$label" "$rec"
	done
	printf '\033[2K\n'
	printf '\033[2K%d to install/update · %d to uninstall\n' "$ins" "$uns"
	printf '\033[2K↑/↓ move · 1-%d toggle · Space mark · a = mark all · Enter = apply · q = cancel\n' "$N"
	CLI_LIST_LINES=$((N + 3))
}

ab_prompt_begin || {
	echo "Interactive terminal input unavailable — use numeric/plain mode instead." >&2
	exit 2
}
while true; do
	render
	ab_prompt_key
	key="$REPLY"
	case "$key" in
	UP) cursor=$(((cursor - 1 + N) % N)) ;;
	DOWN) cursor=$(((cursor + 1) % N)) ;;
	SPACE) MARK[cursor]=$((1 - MARK[cursor])) ;;
	[1-9])
		# Direct toggle on the numbered row, like the shared checkbox menus.
		if [ "$key" -le "$N" ]; then
			cursor=$((key - 1))
			MARK[cursor]=$((1 - MARK[cursor]))
		fi ;;
	a | A) for ((i = 0; i < N; i++)); do MARK[i]=1; done ;;
	q | Q | ESC | CTRL_C)
		ab_prompt_cleanup
		echo ""
		echo "Cancelled — nothing changed."
		exit 0
		;;
	ENTER) ab_prompt_cleanup; break ;; # Enter → apply
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
	IFS='|' read -r id name cmd detect <<<"${AGENTS[$i]}"
	if [ "${INSTALLED[i]}" -eq 1 ] && [ "$id" = "abh" ]; then
		action="Updating"
		run="$cmd"
	elif [ "${INSTALLED[i]}" -eq 1 ]; then
		action="Uninstalling"
		# Derive the uninstall command: every install verb here contains "install"
		# (npm install / brew install --cask / code --install-extension).
		run="${cmd//install/uninstall}"
	else
		action="Installing"
		run="$cmd"
	fi
	echo -e "${CYAN}${action} ${name}${NC} — ${run}"
	# Guardrail (install-only, npm-only): an `npm install -g` against a root-owned global prefix
	# (system Node) dies with a wall of EACCES whose "run manually" hint just reproduces the
	# failure. Catch it first and point at the real fix — nvm-managed Node, never sudo.
	is_npm_install=0
	[ "${INSTALLED[i]}" -eq 0 ] && case "$run" in npm\ *) is_npm_install=1 ;; esac
	# Fresh-machine guard (VS Code extension rows): no `code` CLI means no VS
	# Code — and editors are deliberately NOT installed by agentBrain. Skip
	# with the honest route instead of a bash "command not found".
	case "$run" in code\ *)
		if ! command -v code >/dev/null 2>&1; then
			echo -e "  ${RED}✗${NC} ${name} skipped — VS Code ('code' CLI) not installed. Install VS Code yourself, then re-run setup."
			fail=$((fail + 1))
			continue
		fi ;;
	esac
	# Fresh-machine guard: no npm at all (a Linux install never ran the macOS
	# bootstrap). Offer nvm-managed Node LTS ONCE — same mechanism and pinned
	# nvm version as install-prerequisites.sh — then fall through to the
	# writability guard below. Declining skips every npm row with a clear hint.
	if [ "$is_npm_install" -eq 1 ] && ! command -v npm >/dev/null 2>&1; then
		if [ "${NODE_OFFERED:-0}" -eq 0 ]; then
			NODE_OFFERED=1
			echo -e "  ${YELLOW}!${NC} npm not found — ${name} needs Node."
			if ab_prompt_confirm --default yes "Install nvm-managed Node LTS now?"; then _ans="Y"; else _ans="n"; fi
			if [[ ! ${_ans:-Y} =~ ^[Nn] ]]; then
				curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || true
				export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
				if [ -s "$NVM_DIR/nvm.sh" ]; then
					set +u
					# shellcheck disable=SC1091
					. "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
					set -u
					nvm install --lts && nvm alias default 'lts/*' >/dev/null || true
				fi
				hash -r 2>/dev/null || true
			fi
		fi
		if ! command -v npm >/dev/null 2>&1; then
			echo -e "  ${RED}✗${NC} ${name} skipped — npm not available. Install Node (nvm recommended), then re-run setup."
			fail=$((fail + 1))
			continue
		fi
	fi
	if [ "$is_npm_install" -eq 1 ] && ! npm_global_writable; then
		pfx="$(npm config get prefix 2>/dev/null || echo unknown)"
		echo -e "  ${RED}✗${NC} ${name} skipped — npm global prefix ($pfx) isn't writable (system Node, not nvm)."
		echo -e "     ${YELLOW}↳${NC} Don't sudo. Load nvm-managed Node, then re-run setup:"
		echo "         export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; nvm install --lts && nvm use --lts"
		fail=$((fail + 1))
		continue
	fi
	# Show real output: a wrong/rotted command must fail visibly, never a silent success.
	if eval "$run"; then
		if [ "${INSTALLED[i]}" -eq 0 ] && [ -n "$detect" ]; then
			# Verify the CLI actually RUNS — npm exit 0 alone is not an install. npm's
			# allow-scripts may skip a dep's install script (node-pty gyp build, a
			# postinstall that fetches the platform binary); catch that here, loudly.
			hash -r 2>/dev/null || true
			out="$("$detect" --version </dev/null 2>/dev/null)"; rc=$?
			if [ "$rc" -eq 0 ]; then
				echo -e "  ${GREEN}✓${NC} ${name} (${out%%$'\n'*})"
				ok=$((ok + 1))
			else
				echo -e "  ${YELLOW}⚠${NC} ${name} installed, but '${detect} --version' fails — a dependency install script was likely skipped (npm allow-scripts; see the warnings above)."
				echo "     Fix: re-run with the allow-scripts flag npm printed, e.g.:"
				echo "         ${cmd/npm install -g/npm install -g --allow-scripts=<pkgs>}"
				fail=$((fail + 1))
			fi
		else
			echo -e "  ${GREEN}✓${NC} ${name}"
			ok=$((ok + 1))
		fi
	else
		echo -e "  ${RED}✗${NC} ${name} failed — run manually: ${run}"
		fail=$((fail + 1))
	fi
done

echo ""
echo "Done: ${ok} ok, ${fail} failed. (Re-run setup so agentBrain reflects the change.)"
