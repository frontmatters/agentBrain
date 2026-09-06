#!/usr/bin/env bash
# agentBrain installer — engaging first-run: intro → prerequisites scan → install on request.
set -euo pipefail

# The installer is one versioned unit: this orchestrator, the sub-installers it
# calls (bootstrap-macos.sh / setup.sh / setup-devtools.sh / install-*.sh) and
# the libs they share (platform.sh, lib/capability-install.sh, prompt-helper.sh).
# It evolves independently from the framework it installs; AB_VERSION below is
# the target agentBrain release. Bump installer/VERSION when installer behavior
# changes (see installer/README.md).
# The installer's own version comes from the VERSION file beside this script.
# Piped through `curl | bash` there is no script on disk: BASH_SOURCE is empty,
# dirname of nothing is ".", and the old lookup read whatever VERSION sat in the
# caller's working directory. Measured once: a banner reading "installer
# v1.10.2-prerelease-69" because the shell stood in an older checkout. Piped,
# the version is fetched from the same place the code comes from.
_ab_installer_version() {
  local here
  # Only the installer's own file counts: sourced from a helper, or piped,
  # the file beside BASH_SOURCE is not the installer's VERSION.
  if [ "$(basename "${BASH_SOURCE[0]:-}")" = "install.sh" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -f "$here/VERSION" ] && { tr -d '[:space:]' < "$here/VERSION"; return 0; }
  fi
  local raw="${AB_INSTALLER_VERSION_URL:-https://raw.githubusercontent.com/frontmatters/agentBrain/${AB_BRANCH:-main}/scripts/installer/VERSION}"
  curl -fsSL --max-time 3 "$raw" 2>/dev/null | tr -d '[:space:]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' || echo unknown
}
INSTALLER_VERSION="${AB_INSTALLER_VERSION:-$(_ab_installer_version)}"

# Inlined from scripts/lib/lineage.sh (the piped installer has no lib beside it;
# test-lineage-switch.sh keeps the two copies identical).
lineage_identity() {
	git -C "$1" describe --tags --match 'v*' 2>/dev/null || true
}

adopt_lineage() {
	local dir="$1" src="$2" branch="$3"
	# +refs/tags/*:refs/tags/* forces same-named tags; --prune-tags drops the
	# ones the source does not carry, so nothing from the other lineage lingers.
	git -C "$dir" fetch -q --force --prune --prune-tags --tags "$src" "$branch" || return 2
	git -C "$dir" reset -q --hard FETCH_HEAD || return 2
	[ -n "$(lineage_identity "$dir")" ]
}

B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; M=$'\033[35m'; N=$'\033[0m'
REPO="${AB_REPO:-https://github.com/frontmatters/agentbrain.git}"
BRANCH="${AB_BRANCH:-main}"
DEST="${AB_DEST:-$HOME/Developer/agentBrain}"
# AB_BUNDLE (optional): URL of a git bundle — used INSTEAD of cloning REPO (LAN/dev installs).
# AB_REMOTE (optional): remote URL to set as origin after a bundle install, so pull/update work.
slp() { sleep "$1" 2>/dev/null || true; }
type_() { local s="$1" d="${2:-0.014}" i; for ((i=0;i<${#s};i++)); do printf '%s' "${s:i:1}"; slp "$d"; done; printf '\n'; }
ln_() { printf '%b\n' "$1"; }
# Probe the controlling terminal. A /dev/tty device can exist in SSH batch mode
# while still being unusable.
has_tty() { [ -r /dev/tty ] && tty -s </dev/tty 2>/dev/null; }
# Embedded from scripts/installer/prompt-helper.sh so the website/LAN installer is standalone.
# Keep this block synchronized when the helper changes.
# SPDX-License-Identifier: Apache-2.0
# prompt-helper.sh — dependency-free interactive menus for the installer.
# Source this file; results are returned in the global REPLY variable.
# Bash 3.2 compatible. The menu block renders ONCE below the current output
# and is redrawn strictly in place (same line count every frame); the rest of
# the screen is never touched. Key input blocks until a real key arrives, so
# timeouts can never be mistaken for Enter.

AB_PROMPT_TTY="${AB_PROMPT_TTY:-/dev/tty}"
AB_PROMPT_DEBUG="${AB_PROMPT_DEBUG:-}"
AB_PROMPT_LAYOUT="${AB_PROMPT_LAYOUT:-vertical}"
ab_dbg() { [ -n "$AB_PROMPT_DEBUG" ] && printf '%s\n' "$*" >> "$AB_PROMPT_DEBUG" || true; }
AB_PROMPT_OLD_STTY=""
AB_PROMPT_ACTIVE=0
AB_PROMPT_LINES=0

ab_prompt_restore() {
	if [ "$AB_PROMPT_ACTIVE" = 1 ] && [ -n "$AB_PROMPT_OLD_STTY" ]; then
		stty "$AB_PROMPT_OLD_STTY" <&3 2>/dev/null || true
	fi
	AB_PROMPT_ACTIVE=0
}

ab_prompt_cleanup() {
	ab_prompt_restore
	printf '\033[?25h' >&3 2>/dev/null || true
}

ab_prompt_begin() {
	exec 3<> "$AB_PROMPT_TTY" || return 1
	AB_PROMPT_OLD_STTY="$(stty -g <&3 2>/dev/null || true)"
	[ -n "$AB_PROMPT_OLD_STTY" ] || return 1
	stty -icanon -echo -icrnl min 1 time 0 <&3 2>/dev/null || return 1
	ab_dbg "begin old=[$AB_PROMPT_OLD_STTY]"
	AB_PROMPT_ACTIVE=1
	AB_PROMPT_LINES=0
	trap 'ab_prompt_cleanup; exit 130' INT TERM HUP
	printf '\033[?25l' >&3
}

# Read one complete key event and return a semantic token in REPLY.
# The FIRST byte is read with a blocking terminal (min 1) — no timeout, so
# waiting can never look like a keypress. Only the tail of an ESC sequence is
# read with a short timeout, which is safe on bash 3.2 (integer timeout).
ab_prompt_key() {
	local raw rest
	raw=""
	# Replay bytes swallowed by an earlier lone-ESC tail read (e.g. Esc then a
	# quick Enter): deliver them as ordinary key events first.
	if [ -n "${AB_PROMPT_PENDING:-}" ]; then
		raw="${AB_PROMPT_PENDING%"${AB_PROMPT_PENDING#?}"}"
		AB_PROMPT_PENDING="${AB_PROMPT_PENDING#?}"
		ab_dbg "replay raw=$(printf '%q' "$raw")"
		case "$raw" in
			$'\r'|$'\n') REPLY=ENTER ;; ' ') REPLY=SPACE ;;
			$'\003') REPLY=CTRL_C ;; $'\033') REPLY=ESC ;; *) REPLY="$raw" ;;
		esac
		return
	fi
	# -d '' (NUL delimiter) is essential: with the default newline delimiter,
	# a LF keypress makes read return SUCCESS with an empty variable, which we
	# would misread as EOF. Newlines must arrive as data.
	IFS= read -r -s -d '' -n 1 -u 3 raw || true
	ab_dbg "key raw=$(printf '%q' "$raw") hex=$(printf '%s' "$raw" | od -An -tx1 | tr -d ' \n')"
	case "$raw" in
		"") REPLY=EOF ;;
		$'\r'|$'\n') REPLY=ENTER ;;
		' ') REPLY=SPACE ;;
		$'\003') REPLY=CTRL_C ;;
		$'\033')
			stty -icanon -echo -icrnl min 0 time 1 <&3 2>/dev/null || true
			rest=""
			IFS= read -r -s -d '' -n 2 -t 1 -u 3 rest || true
			stty -icanon -echo -icrnl min 1 time 0 <&3 2>/dev/null || true
			case "$rest" in
				'[A'|'OA') REPLY=UP ;;
				'[B'|'OB') REPLY=DOWN ;;
				'[C'|'OC') REPLY=RIGHT ;;
				'[D'|'OD') REPLY=LEFT ;;
				'[H'|'OH') REPLY=HOME ;;
				'[F'|'OF') REPLY=END ;;
				*)
					REPLY=ESC
					# Bytes after a lone Esc are real keypresses — replay them.
					if [ -n "$rest" ]; then AB_PROMPT_PENDING="$rest"; fi
					;;
			esac
			;;
		*) REPLY="$raw" ;;
	esac
}

# Move the cursor back to the top of our own block (if one is on screen).
ab_prompt_rewind() {
	if [ "$AB_PROMPT_LINES" -gt 0 ]; then
		printf '\033[%sA' "$AB_PROMPT_LINES" >&3
	fi
}

# Redraw exactly $AB_PROMPT_LINES lines every frame. Callers MUST keep the
# printed line count equal to the rewind distance — that invariant is what
# prevents the duplicated-lines bug.
# Render rows arrow-navigable, in one of three view styles:
#   0 numbered   ▸ 1) keep — present and fine     (default row gets "(default)")
#   1 checkbox   ▸ 1) [x] addon                   (multi-select)
#   2 plain      ▸ keep — present and fine        (no numbers)
# Args: title cursor selected style dflt help rows...
ab_prompt_render() {
	local title="$1" cursor="$2" selected="$3" style="$4" dflt="$5" help="$6"; shift 6
	local i label marker box suffix count=$#
	ab_prompt_rewind
	printf '\033[2K%s\n' "$title" >&3
	for ((i=1; i<=$#; i++)); do
		label="${!i}"
		marker=' '
		if [ "$i" -eq "$cursor" ]; then marker='▸'; fi
		suffix=''
		if [ "$style" != 1 ] && [ "$i" = "$dflt" ]; then suffix=' (default)'; fi
		if [ "$style" = 1 ]; then
			box='[ ]'
			case " $selected " in *" $i "*) box='[x]' ;; esac
			printf '\033[2K%s %d) %s %s%s\n' "$marker" "$i" "$box" "$label" "$suffix" >&3
		elif [ "$style" = 2 ]; then
			printf '\033[2K%s %s%s\n' "$marker" "$label" "$suffix" >&3
		else
			printf '\033[2K%s %d) %s%s\n' "$marker" "$i" "$label" "$suffix" >&3
		fi
	done
	printf '\033[2K%s\n' "$help" >&3
	AB_PROMPT_LINES=$((count + 2))
}

# Single-choice enum. Result: REPLY contains the zero-based option index.
# Options: [--default N] [--required] — orientation of the question.
# --default N   1-based option the cursor starts on (shown with "(default)")
# --required    Esc does NOT cancel; the question must be answered
ab_prompt_select() {
	local dflt=1 required=0
	while :; do
		case "${1:-}" in
			--default) dflt="$2"; shift 2 ;;
			--required) required=1; shift ;;
			*) break ;;
		esac
	done
	local title="$1"; shift
	local count=$# cursor=$dflt
	local key
	REPLY=0
	[ "$count" -gt 0 ] || return 2
	case "$cursor" in ''|*[!0-9]*) cursor=1 ;; esac
	[ "$cursor" -ge 1 ] && [ "$cursor" -le "$count" ] || cursor=1
	ab_prompt_begin || return 2
	local nums="1-$count"
	if [ "$count" -gt 9 ]; then nums="1-9"; fi
	while :; do
		local selhelp="↑/↓ navigate · $nums choose directly · Enter confirms cursor · Esc cancel"
		if [ "$required" = 1 ]; then selhelp="$selhelp (required)"; fi
		ab_prompt_render "$title" "$cursor" "" 0 "$dflt" "$selhelp" "$@"
		ab_prompt_key; key="$REPLY"
		case "$key" in
			UP) cursor=$((cursor - 1)); if [ "$cursor" -lt 1 ]; then cursor=$count; fi ;;
			DOWN) cursor=$((cursor + 1)); if [ "$cursor" -gt "$count" ]; then cursor=1; fi ;;
			HOME) cursor=1 ;; END) cursor=$count ;;
			ENTER) REPLY=$((cursor - 1)); ab_prompt_cleanup; return 0 ;;
			ESC|CTRL_C)
				if [ "$required" = 1 ]; then continue; fi
				ab_prompt_cleanup; return 1 ;;
			EOF) ab_prompt_cleanup; return 1 ;;
			[1-9])
				# A number CHOOSES that option immediately — no extra Enter.
				if [ "$key" -le "$count" ]; then
					REPLY=$((key - 1)); ab_prompt_cleanup; return 0
				fi ;;
		esac
	done
}

# Multi-choice checkbox menu. Result: REPLY contains space-separated zero-based indices.
# Options: [--default "1 3"] [--required] — 1-based preselected rows.
ab_prompt_multi() {
	local dflt="" required=0
	while :; do
		case "${1:-}" in
			--default) dflt="$2"; shift 2 ;;
			--required) required=1; shift ;;
			*) break ;;
		esac
	done
	local title="$1"; shift
	local count=$# cursor=1 selected="" key i
	REPLY=""
	[ "$count" -gt 0 ] || return 2
	for i in $dflt; do
		case "$i" in ''|*[!0-9]*) continue ;; esac
		if [ "$i" -ge 1 ] && [ "$i" -le "$count" ]; then selected="$selected $i"; fi
	done
	selected="${selected# }"
	ab_prompt_begin || return 2
	local nums="1-$count"
	if [ "$count" -gt 9 ]; then nums="1-9"; fi
	while :; do
		local mulhelp="↑/↓ move · $nums toggle · Space toggle · Enter apply · Esc cancel"
		if [ "$required" = 1 ]; then mulhelp="$mulhelp (required)"; fi
		ab_prompt_render "$title" "$cursor" "$selected" 1 0 "$mulhelp" "$@"
		ab_prompt_key; key="$REPLY"
		case "$key" in
			UP) cursor=$((cursor - 1)); if [ "$cursor" -lt 1 ]; then cursor=$count; fi ;;
			DOWN) cursor=$((cursor + 1)); if [ "$cursor" -gt "$count" ]; then cursor=1; fi ;;
			HOME) cursor=1 ;; END) cursor=$count ;;
			SPACE|'t'|'T')
				case " $selected " in *" $cursor "*) selected="$(printf '%s' " $selected " | sed "s/ $cursor / /g; s/^ *//; s/ *$//")" ;; *) selected="$selected $cursor" ;; esac
				;;
			ENTER)
				REPLY=""
				for i in $selected; do REPLY="$REPLY $((i - 1))"; done
				REPLY="${REPLY# }"
				ab_prompt_cleanup; return 0 ;;
			ESC|CTRL_C)
				if [ "$required" = 1 ]; then continue; fi
				ab_prompt_cleanup; return 1 ;;
			EOF) ab_prompt_cleanup; return 1 ;;
			[1-9])
				# Direct toggle, like the classic numbered checklists.
				if [ "$key" -le "$count" ]; then
					cursor="$key"
					case " $selected " in *" $cursor "*) selected="$(printf '%s' " $selected " | sed "s/ $cursor / /g; s/^ *//; s/ *$//")" ;; *) selected="$selected $cursor" ;; esac
				fi ;;
		esac
	done
}

# Yes/no confirmation. Result: 0 for yes, 1 for no/cancel.
# Renders exactly 3 lines (title, Yes/No, help) and rewinds exactly 3 lines.
# Options: [--default yes|--default no] [--layout vertical|inline]
# Layout orientation: per-question via --layout, globally via AB_PROMPT_LAYOUT
# (default: vertical — Yes/No as numbered rows like every other question).
ab_prompt_confirm() {
	local dflt="yes" layout="$AB_PROMPT_LAYOUT"
	while :; do
		case "${1:-}" in
			--default) dflt="$2"; shift 2 ;;
			--layout) layout="$2"; shift 2 ;;
			*) break ;;
		esac
	done
	local title="$1" answer key
	if ! ab_prompt_begin; then
		case "$dflt" in no) printf '%s [y/N] ' "$title" ;; *) printf '%s [Y/n] ' "$title" ;; esac > "$AB_PROMPT_TTY" 2>/dev/null
		read -r answer < "$AB_PROMPT_TTY" || answer=""
		case "$answer" in
			"") [ "$dflt" = no ] && return 1 || return 0 ;;
			[Yy]*) return 0 ;; *) return 1 ;;
		esac
	fi
	local cursor=1 dflt_row=1
	if [ "$dflt" = no ]; then cursor=2; dflt_row=2; fi
	local help="←/→ or ↑/↓ navigate · 1/2 or y/n direct · Enter confirm · Esc cancel"
	while :; do
		if [ "$layout" = inline ]; then
			ab_prompt_rewind
			local yes='  ' no='  '
			if [ "$cursor" = 1 ]; then yes='▸ '; fi
			if [ "$cursor" = 2 ]; then no='▸ '; fi
			printf '\033[2K%s\n' "$title" >&3
			printf '\033[2K%s1) Yes      %s2) No\n' "$yes" "$no" >&3
			printf '\033[2K%s\n' "$help" >&3
			AB_PROMPT_LINES=3
		else
			ab_prompt_render "$title" "$cursor" "" 0 "$dflt_row" "$help" "Yes" "No"
		fi
		ab_prompt_key; key="$REPLY"
		ab_dbg "confirm key=$key cursor=$cursor lines=$AB_PROMPT_LINES"
		case "$key" in
			LEFT|UP|HOME) cursor=1 ;; RIGHT|DOWN|END) cursor=2 ;;
			'y'|'Y'|'1') ab_prompt_cleanup; return 0 ;;
			'n'|'N'|'2'|ESC|CTRL_C|EOF) ab_prompt_cleanup; return 1 ;;
			ENTER) ab_prompt_cleanup; [ "$cursor" = 1 ] && return 0 || return 1 ;;
		esac
	done
}

# Free-form text input. Options: [--default "value"] [--required]
# Result: REPLY contains the entered line (trimmed). The terminal stays in
# normal (canonical) mode so backspace/line-editing work.
ab_prompt_text() {
	local dflt="" required=0
	while :; do
		case "${1:-}" in
			--default) dflt="$2"; shift 2 ;;
			--required) required=1; shift ;;
			*) break ;;
		esac
	done
	local title="$1" line=""
	[ -n "$title" ] || return 2
	if [ "$required" = 1 ]; then title="$title (required)"; fi
	printf '\033[2K%s' "$title" >&3
	if [ -n "$dflt" ]; then printf ' [%s]' "$dflt" >&3; fi
	printf ': ' >&3
	while :; do
		line=""
		IFS= read -r line < "$AB_PROMPT_TTY" || line=""
		if [ -z "$line" ] && [ -n "$dflt" ]; then line="$dflt"; fi
		if [ -n "$line" ]; then REPLY="$line"; return 0; fi
		if [ "$required" = 0 ]; then REPLY=""; return 0; fi
		printf '\033[2K%s (required): ' "$title" >&3
	done
}

# Standalone CLI mode for Python onboarding and other clients. The UI uses the
# controlling terminal; only the selected index/result is printed to stdout.
if [ "${AB_PROMPT_HELPER_STANDALONE:-}" = 1 ]; then
	mode="${1:-}"; shift || true
	case "$mode" in
		select) title="${1:-Choose}"; shift; ab_prompt_select "$title" "$@" && printf '%s\n' "$REPLY" ;;
		multi) title="${1:-Choose}"; shift; ab_prompt_multi "$title" "$@" && printf '%s\n' "$REPLY" ;;
		confirm) ab_prompt_confirm "${1:-Continue?}" ;;
		text)
			_dv=""
			while [ "${1:-}" = "--default" ]; do _dv="$2"; shift 2; done
			if [ -n "$_dv" ]; then ab_prompt_text --default "$_dv" "${1:-Input}"; else ab_prompt_text "${1:-Input}"; fi
			printf '%s\n' "$REPLY" ;;
		*) printf 'usage: %s {select|multi|confirm} ...\n' "$0" >&2; exit 2 ;;
	esac
	exit $?
fi

clear 2>/dev/null || true   # audit-ok: intro starts from a clean screen, by design
printf '\033[?25l'
_anim=$(cat <<'BRAIN'
@@@
  
                    ⢀ ⠠⢄⡀⢀⢀⡄
             ⢀  ⢠⢠⣐⠢⢘⣧⠁⠂⣷⡺⡀⢢⡌⢦⠈⠭⠁⢆⡀⢜⣀⢀
        ⠠⡀ ⡂⡀⠊⢂⠤⠔⡅⡕⠗⢡⡐⠔⠰⢸⢀⢠⢀⡢⣖⣥⡾⡖⠣⣵⠤⡾⠣⠐⣣⠠
         ⠰⢊⢪⡂⣆⠓⠖⡫⠫⢎⣢⠃⠳⠤⢁⠌⠇⠂⠢⠌⠵⢐⠅⡱⡐⣒⠋⢎⠈⢧⠵⠳⠂⡢⢰⡀
        ⢁⢌⡈⠹⠔⣬⡉ ⡅⠈⠆⡰⡀⠄⡂⡀⢁⣎⠂⠔⢢⠸⡐⣰⢙⡉⡖⠒⠐⠄⡀⡲⣆⡚⢳⠨⠡
      ⠠⠑⠡⡱⢓⡆⣰⡓⠔⠌⡱⠜⠄⡂⠎⢩⠈⡔⠉⡢⡤⠐⠨⡀ ⡘⠑  ⢈⠤⡢⢀⢵⡹⢠⡚⢃⠄⠁⢀
       ⣚⠑⡩⢽⢶⣉⣍⡚⢀⣁⠈⠂⡐⢀⠌⡠⠴⠄⠄⡀⠕⢕ ⠔⠠⣇⡊⠤⢆⠔⠒⢖⣟⡆⣳⡄⣇⡅⠆⠂
       ⠁ ⡟⠈⣿⡜⣕⡒⡨⠠⡬⠜⠠⢒⢡⠐⢰⠄⠬⣪⣤⠐⠬⡙⠭⠂⣲⠄⢉⣬⡎⡒⢿⣯⠍⠓⠃⠔⠂
         ⠁⠂⢙⢷⡟⣻⡎⣓⢱ ⢩⡅⢥⣠⠦⡼⣖⡲⣠⠽⣸⠔⣘⢨⢇⢈⣳⣝⡿⣉⠵⠜⠐⠉
         ⠐⠠⠎⣜⣸⣻⣽⣑⢯⠬⣋⡻⡘⢪⣡⡵⠛⣫⠾⢇⢿⡢⡿⢻⣫⠛⡜⢡⠋
           ⡧⠕⠜⣟⣚⢬⢃⢭⠇⠃⠈⠁⠐⠈⠐⠂⠉ ⠈ ⠁⠘⠂
             ⠁⠈ ⢈⢪⡕⠂
                ⠠⣇⠃
                ⠈⠓
  
@@@
  
                     ⢠⡀⡀⠠⢀⣄⡀
             ⡀ ⢠⢠⡀⡰⡒⢄⡍⢕⣲⠔⢨⣔⡽⣢⠥⠩⠁⠇⣡⡎ ⣀⣀
        ⠄⡀⠐ ⠂⡑⡀⠤⡰⣧⠰⢋⡅⠊⣌⢀ ⢐⢲⠈⣤⣒⣚⢆⣼⠇⢨⡧⣇⢿⠔⢁⡀⠄
         ⠐⠂⡜⠰⠁⢖⣨⠘⠍⡏⠑⢺⡴⠓⠑⠠⠮⡨⠇⠔⠁⣚⠠⡢⡉⠨⠚⢢⢕⠻⠘⠘⠔⡒⣤
        ⠡⢀⡨⣑⠅⠑⠤⠈⣡⢠⠁⡔⢆⢐⡄⠪⡐⠰⠍⢀⢓⣠⡊⣂⠔⢨⢊⠅⠄⢲⠲⢒⣜⠐⠌⠺⠥
       ⠰⠬⡁⡃⡚⠒⡪⣀⠞⡀⠎⠅⠌⢥ ⡰⠈⢀⠥⢆⠉⡢⠁⠖⠁ ⠘⢰  ⣱⢥⢆⡽⠒⣖⠉⡣ ⢀
       ⢐⢑⣕⢱⣭⢚⡙⡊⢑⠁⡂⡈⢁⠤ ⢆ ⢄⡀⠦⠐⠄⠌⣹⠇⢆⠄⢞⣐⢢⠔⠖⢖⣜⣶⡅⠯⡪⠂⠂
        ⠱⡃⠽⢽⠺⣃⣝⡍⢜⠂⡀⡅⢄⠦⠌⠔⡄⠂⡏⡩⢨⣧⣤⠦⡄⡼⠰⡑⡠⢛⣽⣷⣜⠎⠱⠒
         ⠁⠑⡚⣫⡯⢧⣻⣴⡑⠍⢰⡶⣤⣝⡬⢄⡔⣴⣶⠒⢡⠥⡇⢅⢃⣴⣍⢽⡛⠱⡽⠖⠉⠂⠁
          ⠔⢬⢙⣗⣿⡯⡾⣇⣩⠽⢊⢫⡟⢶⢍⢻⠾⢵⣏⡟⠷⣅⡶⠳⡻⡍⠏⠉⠁
           ⡄⠇⠏⣮⡹⡟⡫⡭⡜ ⠋ ⠁⠂ ⠚⠈ ⠁⠁⠊⠐⠁
             ⠁⠈ ⠈⣘⢬⠂
                 ⣜⠘
                ⠈⠙
  
@@@
  
                    ⡀⠄⡀ ⣀⢤ ⢀
             ⢀ ⢄⣄ ⢂⢂⣆⠷⡳⢸⡲⢀⢨⠚⢢⡭⠔⢡⡣⠉⣠ ⣀⡀
         ⠄⡀⠐⠂⠘⠢⣠⠆⡷⠔⡶⠡⡈⠁⣁⡦⠋⡄⡐⠲⠪⢷⡢⣈⡯⣮⢗⠼⡫⠊⡀⡄
           ⢂⡐⢡⠲⠈⢇⢋⢊⠕⠕⠁⠐⣮⠼⠁⠐⠯⣢⢀⠪⠈⠉⠆⡍⡖⡻⢐⠇⢂⢸⡗⠆⡀
         ⠨⢠⣫⡁⢨⠉⢅⠣⠠⡋⣠⠜⠑⢰⠅⡂⡐⣠⡐⡋⠐⢊⡢⠠ ⡸⣬⠣⢄⡑⡦⡃⠨⠸⠪
        ⠐⠌⣖⠉⠑⢐⡚⠐⡣⣨⢒⡅⠬⠤⠤⢡⠄⡰⠉⡘⠂⠄⢙⢔⠄⢇⠐⠱⡔⣈⠔⣺⡤⢣⣣⠨⠂⡀
        ⢀⣊⣟⣾⢋⡱⠐⢁⡃⠨⠇⢡⠂⠬⣀⠄⠲ ⠌⣌⠄⡆ ⠰⡘⢐⠡⠖⢊⣆⣰⢦⠺⣜⢩⠸⠐
         ⠢⡎⠹⡵⠯⠹⢇⣈⣋⠡⠸⡔⡤⠈⢨⡊⠌⠰⢀⣢⢤⢉⣜⢥⢒⠦⠱⠻⢿⣇⣾⣶⡓
          ⠙⢺⡛⢞⠻⠿⡬⣨⣿⣦⢇⠩⣑⡄⣴⢌⢭⡰⢄⢣⠳⡨⣤⡸⡽⡼⣽⢛⢫⠷ ⠊⠈
           ⠦⡏⢻⢝⣯⡵⣽⢗⣅⣯⡭⠓⣞⢱⣯⠺⣻⣫⣼⢘⠻⡶⡜⠜⠃⠇⠋⠁
            ⡌⠠⢙⠣⣵⣷⣫⠭⡆⠁⠃ ⠈⠂⠃⠂⠉⠐⠁⠊ ⠁
             ⠈ ⠈ ⠈⣊⢼⠂
                  ⡕⠊
                 ⠈⠙
  
@@@
  
                   ⡀⠠⡀ ⢀⠄⡀⡀⠄⡀
              ⢀⠠⡄⡂⡀⡀⡎⡰⡆⡼⠢⣉⠇⣛⠔⢾⣬⣉⠅⢁⢄⢀⡀
           ⠄⡀⠂⠰⠕⣢⣤⠱⣴⢆⢨⡢⣙⢌⢑⡀⠖⣕⠤⢲⣶⡟⡨⣿⢭⠮⢂⡢⡀
             ⡒⡷⠎⡛⠶⠝⢅⢋⠗⢾⠌⠚⣢⣘⡞⠈⠩⢠⡄⠆⢭⠲⠱⣒⡖⠁⡶⢫⠂
           ⡠⣯⠡⢀⢥⡰⣩⠓⠪⠇⠈⢀⣊⣔⠆⣑⠂ ⡤⠘⠒⡮⡦⣊⣸⠗⣇⠆⢚⠡⠪
          ⠔⡟⢑⣌⠂⠫⠡⡢⠅⢀⢆⠐⢊⡌⠔⠤⠈⠤⢞⠌⡐⠃⢴⣇⠈⠲⢓⢨⢁⢮⢆⠠⡅⠂
         ⡈⢀⣻⡻⡄⢒⡀⢥⠴ ⡽⠈⠆⠫⢱⢁⣣⡀⠐⡲⢰⡢⠴⢒ ⣎⡲⢱⠊⣶⡜⣽⡻
           ⢧⡫⢬⢗⡀⠣⠵⢯⢌⣊⠉⠅⢆⣐⡤⡁⠆⡌⠔⡂⡮⡄⣿⢷⡦⣤⣖⣿⣳⡓⡀
           ⠔⣓⢫⠙⣷⡸⣗⣯⣤⢥⣸⠧⢊⣁⣜⡉⠠⡧⣕⡸⣳⠌⡥⢱⣻⢫⡧⠛⠇⠊
            ⠐⢬⠋⣫⢿⢼⣵⡯⣏⡞⠕⣼⣿⣿⣿⣚⢿⡵⣟⠰⡓⠪⠣⠹⠣⠊⠁
             ⠠⡈⢴⠹⢮⢾⣻⡦⡽ ⠐ ⠁⠓⠚⠈⠐⠁⠁⠈
               ⠈ ⠁ ⢑⣱⠕
                   ⣹⠐⠁
                   ⠉⠃
  
@@@
  
                  ⢀ ⠠⡄⢀⠠⢀   ⣄⡀
                ⢠⡆⣀⡂⣄⠗⠔⣐⢮⠎⢽⢒⣈⠿⣥⠍⣈⣠⡀
              ⠄⡶⠆⡃⣢⠬⡲⣇⢦⠈⠆⣅⠋⢱⣄⠺⠈⣒⢗⡽⠷⣁⣖⡀
              ⡠⣻⡞⡣⠃⠼⠲⠇⢞⢁⡊⠿⡅⢰⣖⠌⢗⠊⣄⡜⠾⢗⡆⣷⠨⠃
            ⢀⢈⡦⡽⡖⠡⠃⢀⣘⣋⠐⠏⠊⠁⢰⡑⢦⣆⡄⣡⠎⠠⠋⣏⠮⣆⢺
           ⠐⢡⡘⡏⢯⡅⠠⢀⢉ ⠓⠁⢀⣰⣒⠌⡔⠤⣜⠨⠞⣓⠁⡼⠙⢝⡦⣤⡌⠔
          ⢀⣉⣲⡁⣮⢿⠠⡤⠒⠠⢍⢐⠠⠊⡋⠢⡙⢒⣕⢂⢲⢲⣆⠔⠂⠸⣎⣆⣧⡮
           ⠈⢢⢜⡭⢯⢽⡫⠁⠥⠃⢹⣬⣀⣃⠁⠇⣃⡔⠙⠿⢆⠲⣴⣬⣸⣷⢺⢲⣖⡁
            ⠄⡓⡺⠿⣿⡫⣌⣴⢿⣎⣤⣅⡹⡒⢉⣩⣱⠫⡭⣞⣵⣮⢿⡝⠿⠙⠍⠐
               ⠻⣝⣻⣽⡿⣾⡿⢿⣯⣷⢾⣥⢹⣛⢋⡾⢻⠛⠫⠏⠏⠖ ⠁
                ⢌⢕⠍⢻⠻⣽⣫⠮⠘⠂⠈⠚⠊ ⠁⠈
                 ⠈ ⠈⠈⢘⡦⠇
                     ⡽⠊
                     ⠙
  
@@@
  
                  ⡀  ⡤⡀⠄⡀    ⣄
                 ⠂⢲⣀⢠⠜⢒⡟⠿⣢⡩⠰⡨⢁⢇⣇⡅⢀
               ⠰⠤⠶⣴⢜⣴⡬⢶⢀⢔⡵⢌⢇⠊⢙⡔⣝⠿⡗⡢⡃⣄⡀
              ⠐⢑⢜⠫⣗⠋⣚⣪⠃⠁⡦⠯⡋⣐⢍⠖⣖⠲⡵⢻⡞⠬⠼⡀
              ⢀⡗⣶⢅⣜⢁⠂⠑⠐⠰⡃⣏⠜⣥⡋⠄⢱⢒⠌⡭⡝⠮⣰⣒
             ⡜⢠⡳⣖⢃⠕⢋⠁⢂⠬⠑⢨⠆⡅⢂⡳⠒⢁⠬⠪⣷⣥⡩⠏⢳⠤
            ⢁⣣⣼⣤⡣⢯⡮⣗⡐ ⡲⢂⠜⣗⠂⢆⡃⠊⠙⢃⡞⣦⢵⢞⢜⠏⣎
             ⢱⡩⡥⠭⠫⢽⣋⠎⠘⠈⠄⡃⠚⣽⡳⡍⡚⠱⣄⣿⢶⣖⣾⣗⣦⡖⣑
              ⠜⣮⣶⡿⠯⣏⣅⣅⣊⢼⠧⣡⣭⠓⢞⠊⣪⠦⣿⣟⡿⠯⠗⠙⠁
                ⠉⠋⡻⣮⣿⡿⣾⣽⣞⣾⡵⢓⢨⡞⣯⡚⠳⠟⠧⠂ ⠁
                  ⠁⢄⡏⠩⡟⢯⣳⡪⠳⠒⠊⠉⠁
                    ⠈ ⠁⢙⡴⠅
                       ⡹⠊
                       ⠑⠁
  
@@@
  
                  ⢀  ⣠⠤⢀     ⣀⠄⡀
                  ⢒ ⣠⣼⡗⢱⡗  ⣪⣭⣨⠴⡀⠜⢀⢀
               ⠠⠢⢄⣵⡦⣖⢂⡼⡿⡖  ⣘⡧⢿⣩⡋⢲⣲⢅⣄⢁⡀
              ⠐⠂⠹⢕⣟⢺⢷⢑⡪⣑⡂  ⠹⡿⣼⢼⡗⣾⢋⠵⡄⡠
             ⠈⢒⣆⣚⢲⠗⢵⠲⡴⢭⡙⡄  ⠐⣡⢩⠱⠉⢹⣇⣸⠠⣕⣀⠂
            ⠄ ⣄⣄⢱⢇⣚⠠⣶⠧⡡⡃⡃  ⠸⢈⢺⢬⣠⣣⠻⢵⣯⡕⠝⠠
            ⠠⡤⣽⢽⣨⢚⣔⣢⢚⡸⡾⣜⣂  ⠒⢇⢙⢕⠠⡟⡙⢱⣖⠯⣀⠊
            ⠈⢉⣬⡥⣻⢕⠭⠨⠜⡫⡿⢟⠇  ⢝⢞⣾⡥⣚⢃⡪⣷⣾⡷⣷⡐
               ⢢⢭⢿⠤⣷⠑⣮⢫⣋⢁⢀⣄⢾⣬⡿⢽⡻⣵⡟⣿⠽⡋⠁
                ⠘⠻⢉⠽⢻⣿⣿⣿⡿⣮⣾⢿⣻⣿⡟⡝⣞⠿⠋⠙
                   ⠈ ⠃⢁⢯⢏⠶⡻⡼⢟⠁⠇
                        ⠁⠙⡔⠅
                         ⣱⠏
                         ⠈⠃
  
@@@
  
                   ⢀ ⢀⠤⢄    ⢀⢀⠠ ⢀
                  ⡐⡖⢬⢫⣺⣵⡒⢠⣺⠅⣡⣧⢵⡅⠅⠐⢀
                ⢄⣵⡆⣲⠞⠶⠑⣆⠱⡽⡷⡝⣥⢓⢺⢐⣍⢜⡆⣈⣀
              ⠠⠒⣷⡿⣚⢿⢇⠐⠬⢔⢑⡢⡄⠒⡲⠺⠋⠻⢏⢷⣿⡠⡣⠠
             ⡁⡲⢶⣒⣳⡯⡴⡄⡍ ⡇⢮⠑⢫ ⠁ ⣉⠜⠠⣉⢾⣏⣄⣀⡆
            ⠄ ⢠⡓⣱⢝⢼⠒⠂⡂⡂⡐⡱⡧⢉⢌⢫⢄⠅⠈⢼⠒⠉⣫⡾⣵⠅⠄
            ⠤⣚⠬⣆⢾⣗⢷⡪⣚⡠⢒⢨⡋⢼⣬⠤⣛⡒⠁⠔⠔⠕⢋⢖⢫⠋⣂
           ⠈⢡⢬⣕⠧⣴⠤⢫⢿⠳⠠ ⢺⠌⡵⣥⢐⣑⢂ ⣁⢟⡇⣽⣟⢶⢟⡆⡀
              ⠈⠼⣳⠹⢬⡹⡗⣠⢒⠶⢚⢏⣕⢋⣉⢠⢽⣾⣻⡵⣚⠾⠽⢀⠉
               ⠘⢦⠝⠣⢯⢧⣟⢥⣼⣫⢿⣿⢿⡿⣿⣷⢷⡟⢙⠈⠑ ⠃
                   ⠐ ⠈⠑⠉⠁⢉⠫⢿⣿⢒⡮⢇⠃⠔
                           ⠊⣷⠅
                           ⢈⡯
                            ⠋
  
@@@
  
                     ⣀⢠⢀⠤   ⡀⢀⠠  ⡀
                ⢀⠆⡠⠚⡫⠴⢥⣢⣞⡿⡕⠅⣢⢄⢣⣮⠠ ⣂
              ⡤ ⢴⣵⡕⠴⡜⠴⣻⣺⠯⢘⣧⣺⡞⠳⣢⢭⢠⡳⣉⣁⢁⡀
            ⠠⠈⢓⣜⠾⣩⠎⢁⡣⠆⡧⢴⠰⡝⠪⠺⠃⡊⡞⠨⣚⠑⠽⡧⡸⠧⢀
           ⠠⢐⣃⠾⣷⣂⢅⠉⠲⣘⠖⠤ ⠍⡀⣠⠂⡧⠈⢨⠄⡪⠢⡈⣳⢩⡏ ⣀⠄
            ⡡⡴⣓⣾⡐⢀ ⣃⠱⡔⡙⠔⡂⠴⣠⠁⡐⢌⠁⠣⢑⠉⡸⠛⢻⢿⡟⣥⠴
           ⢤⡎⡶⣗⣖⠴⠐⠄⣹⠫⣁⣠⢬⣋⡖⢁⠌⢂⠼⢼⠎⡸⣂⠨⢸⠰⠋⡉⡃⢉⠂
           ⠨⡏⣟⠳⡼⢭⠱⢴⠊⡭⠉⣧⡆⡲⢂⢀⢨⡸⣵⠧⢃⣏⣮⡺⣦⠿⢞⡎⢆⡃
             ⠅⠈⣭⣛⣇⡦⡡⠦⣷⣩⠻⢏⠏⡼⠓⡺⣯⣪⣽⣷⣚⣮⢷⠾⢁⠊⠈⠁
              ⠐⢼⠅⡹⢳⣏⣰⠝⣍⢽⠿⣷⡙⡟⢿⣿⣿⣿⣾⡟⢾⡉⠈⠚
                  ⠐  ⠂⠉⠉⠈⠈⠉⠛ ⣶⣿⡗⡵⡐⡍⠵⠂
                             ⠂⣯⠄
                             ⢘⡧
                              ⠋
  
@@@
  
                      ⣠⢀⡀⠤ ⢀⢀ ⠠  ⢀
              ⢀ ⠆⠨⢐⣉⣱⠖⡥⠼⠷⣴⡑⣠⣄⣜⢨⢅⡇⡠⢂
            ⡄ ⠔⢆⡡⢼⢦⣾⡷⣸⠯⠳⢬⡓⡢⠲⡢⡶⡼⠒⣯⣚⡠⣩ ⡀ ⢀
           ⣔⠃⡝⢵⣑⡲⡧⠳⠣⠻⠄⡹⠒⢘⠐⠅⡫⠆⢡⠘ ⢀⢟⡯⣾⠻⡿⡆⠁⡄
         ⠄⢐⠇⠓⡖⡜⠴⡟⢒⢀⠌⡀⠐⢀⡠⠰⢭ ⠥⢁⢐⢴⢂⠤⡉⢈⣆⠎⠈⠉⢏⡁⠄
         ⠠⢉⡠⢒⡦⠔⡘⡕⡥⡑⠡⢀⡬⢨⢤⠑⠰⡁⡊⠂⠂⡀⠁⣐⠜⠩⠩⣣⠃⠽⡒⣯⡬⠐
         ⠰⣒⢴⢪⡶⡗⣍⢜⢄⢠⡤⣭⠒⢋⠇⡈⢠ ⣘⡚⣄⣄⠃⢊⠯⠼⡀⠞⢐⢌⢊⠋⢉⠙
         ⠁⠓⢾⠅⢽⣫⡟⢨⡨⢴⡄⣴⣒⢈⣀⣝⢍⢐⠇⢄⡄⠢⢲⣭⡏⡃⠵⡁⢖⠜⢧⣋⣇⠁
           ⠈⠭⠑⣍⢧⡕⢧⣺⣘⠿⢕⡭⣭⢑⢓⠜⡴⣎⣦⢷⡻⣊⣣⣨⣴⡵⢿⠟⠘⠉
             ⠠⠘⣠⠞⡃⢹⡣⡪⢽⣾⠟⣽⡱⠷⣾⡏⠋⣺⣽⢟⣿⣿⡷⡷⡟⠂
                 ⠐ ⠐  ⠁⠉ ⠁⠙⠋⠈⠑⠁⣾⣺⠽⣇⡔⡌⠤⠃
                              ⠐⢸⣧⠉
                               ⣊⡧
                                ⠋
  
@@@
  
                      ⢀⠄⣀⡀⠠⡄⡀ ⠄  ⡀
             ⢀ ⠢⠈⣠⣂⠉⣅⠰⠯⠦⠤⠃⣶⣇⣐⠭⣠⣮⠡⣒⢠
           ⡄ ⠒⠬⣥⣂⢭⡾⣸⡞⠱⣪⣊⢶⠒⢴⣀⠢⢠⢴⡞⠥⡛⣞⡡⢐ ⢀⡄⢀
        ⢀⡐⠠⠖⣍⢴⢊⣔⠲⡞⠵⡕⠗⠓⠛⠈⠬⠓⠈⡇ ⠄⡱⠠⢥⠪⠱⣟⢞⠄⣵⡖⢉⠠
        ⠬⡆⠃⡳⡌⢳⣒⠂⢃⢣⠔⡐ ⡗⢌⡈⠐⠄⣔⠰⠠⡠⠡⡉⢑⢠⠲⡠⠇⢈⠠⢉⣝⢍⢀
       ⠠⢁⡈⡲⢢⢺⠆⣕⠐⡩⣄⠄⠠⢄⡁⢄⢀⠈⠝⡄⠂⠘⠈⢢⠰⠊⢨⢉⢢⠂⠭⠍⢄⡿⡑⡅⠎
       ⠰⢒⣖⣀⢚⡷⠿⣄⡥⣇⣱⠘⡠ ⠄⠤⠄⠐⣙⢐⡅⠘⡀⢑⢚⠴⣀⡨⠐⡴⠩⣁⡐⠟⣒⠑⠋
       ⠈⠲⠑⠂⠸⡏⢝⣖⢽⢩⢰⢢⢀⣕⣡⠠⠸⣀⣁⢔⠡⠞⢌⣵⠇⢂⠤⠂⠼⡗⠳⢥⡊⢓⡇⢩
          ⠁⠝⠍⡭⣯⡦⣝⡨⠮⣪⣕⡒⣼⢯⢤⢇⣴⠥⡝⣱⡢⢶⣦⣐⡿⣹⣍⡷⢧⠍⠛⠈
             ⠄⢁⡲⡭⠘⡩⢱⡶⢝⢧⡯⣗⠾⢯⢜⢗⢡⡲⢙⢿⣿⣵⣿⣿⠿⢆⠄⠂
                 ⠐⠐  ⠈⠁⠁⠉ ⠑⠂⠉⠙⠈⠑⡧⡢⣟⢿⢺⡸⠌⠔⠁
                               ⠐⢐⢽⡀⠁⠁
                                ⢘⡫⠄
                                 ⠊⠁
  
@@@
  
                       ⢀⢄ ⣀⡀⠄⠠  ⢀
             ⡀ ⡰⣁⣠⢂⠈⠭⣙⠨⠤⠣⡦⢒⡺⢪⢀⠄⡌⣲⢰⡠ ⢀
           ⡄⠔⠁⣁⠼⡟⠴⡌⣻⢳⣟⡒⣤⢆⣂⠤⡖⣀⠎⠒⠐⣦⠩⢪⢰⢆⠃ ⢂ ⡠
       ⢀⡂⢆⢐⠇⣯⠜⠶⢉⠱⡂⡊⠲⠊⠭⠜⠒⡨⠁⠠⠐⠁⢱⢈⠠⠧⡴⡺⠫⠇⠢⣓⣆⡔⠃⠠
       ⠌⢄⠟⡐⣷⢀⠢ ⡒⣀⠐⡓⡡⢽⠃⠰⢊⠴⢀⡀⠆⢠⡁⡇⢄⠁⠔⡈⢆⢠⠃⡨⢈⡜⠅⡉⢀
      ⢈⢄ ⡺⢗⣣⠈⡪⢄⠄⠠⠆⡩⣠⠠ ⠑⢄  ⡁⠃⡬⢆⠋⠱⢘⡑⠄⠒⢅⠬⢐⠔⡏⣧⡊⠂⠈⠄
      ⠰⠒⣆⡹⡸⡲⣦⢳⠮⠝⣦⠅⠴⠄⢠⠢⣘⡠⠄⠰⠄⠋⡀ ⡞⢀⢡⣀⢚⡊⢄⣁⠲⡪⢵⡕⠋⡋⠊
       ⠪⠐⠚⠪⠍⡝⣷⣔⣶⣢⡏⣩⠉⠔⢆⡄⠇⡐⠴⠄⣨⡯ ⢃⠌⠆⢑⠦⠂⠠⡄⢽⣛⣓⣿⡋⠅⠁
         ⠁⠘⠕⠫⡭⣋⡛⣪⠏⣓⠨⠲⣥⢱⣲⣤⠱⢅⢶⡄⢼⠐⣀⠥⡟⢦⣅⣺⣻⢻⣷⠉⠘
             ⠠⢘⠱⡙⠽⣝⠟⢵⢷⢧⠧⡣⡗⡋⢻⠄⣣⠟⡒⢛⢥⣿⣽⡿⣿⣿⢆⠤⠐
                  ⠒ ⠁⠉ ⠉ ⠈⠒  ⠋⠉⠘⢱⠌⡂⡝⡣⢳⡽⡜⠔⠁
                                ⠐⡪⣎ ⠈ ⠁
                                 ⢊⡫
                                  ⠋
  
@@@
  
                        ⢠⡀⡀⢀⡠⠄ ⡀
              ⡀⣀⡣⢀⡰⠈⠭⠁⡴⢡⡔⢀⢗⣾⠐⠈⣼⡃⠔⣂⡄⡄  ⡀
           ⠄⣜⠂⠜⢷⠤⣮⠜⢲⢷⣬⣲⢔⡀⡄⡀⡇⠆⠢⢂⡌⠺⢪⢨⠢⠤⡐⠑⢀⢐ ⢀⠄
       ⢀⡆⢔⠐⠞⠮⡼⠁⡱⠙⣒⢂⢎⠨⡂⠮⠡⠔⠐⠸⠡⡈⠤⠞⠘⣔⡱⠝⢝⠲⠚⣰⢐⡕⡑⠆
       ⠌⠅⡞⢓⣰⢖⢀⠠⠂⠒⢲⢉⡋⣆⢂⠇⡔⠢⠐⣱⡈⢀⢐⠠⢀⢆⠰⠁⢨ ⢉⣥⠢⠏⢁⡡⡈
     ⡀⠈⠠⡘⢓⡄⢏⡮⡀⢔⠤⡁  ⠊⢃ ⢀⠅⠂⢤⢔⠉⢢⠁⡍⠱⢐⠠⠣⢎⠡⠢⢚⣆⢰⡚⢎⠌⠊⠄
     ⠐⠰⢨⣸⢠⣞⢰⣻⡲⠒⠢⡰⠤⢑⣸⠄⠢ ⡪⠪⢀⠠⠠⠦⢄⠡⡀⢂⠐⠁⣈⡀⢓⣩⣉⡶⡯⢍⠊⣓
      ⠐⠢⠘⠚⠩⣽⡿⢒⢱⣥⡉⠠⣖⠐⠭⢋⠥⠂⣤⣕⠥⠠⡆⠂⡌⡒⠄⠣⢥⠄⢅⢒⣪⢣⣿⠁⢻ ⠈
         ⠉⠂⠣⠮⣉⢿⣫⣞⡁⡸⡅⣃⠢⣇⠯⣄⢖⣲⢧⠴⣄⡬⢨⡍ ⡎⣚⢱⣟⢻⡾⡋⠐⠈
              ⠙⡌⢣⠛⣝⡟⢿⢔⡿⡸⠷⣝⠛⢮⣌⡕⢃⢟⣙⠥⡽⣊⣯⣟⣇⣣⠱⠄⠂
                  ⠐⠃⠈ ⠁ ⠉⠐⠂⠁⠂⠈⠁⠘⠸⡭⡘⡥⣓⣻⠣⠪⢼
                                ⠐⢪⡕⡁ ⠁⠈
                                 ⠘⣸⠄
                                  ⠚⠁
  
@@@
  
                        ⢀⣠⡀⠄⢀⢀⡄
              ⣀⣀ ⢱⣌⠸⠈⠍⠬⣔⢯⣢⡅⠢⣖⡪⢩⡠⢒⢆⢀⡄⡄ ⢀
          ⠠⢀⡈⠢⡿⣸⢼⡅⠸⣧⡰⣓⣒⣤⠁⡖⡂ ⡀⣡⠑⢨⡙⠆⣼⢆⠤⢀⢊⠐ ⠂⢀⠠
        ⣤⢒⠢⠃⠃⠟⡪⡔⠓⠅⢉⢔⠄⣓⠈⠢⠸⢅⠵⠄⠊⠚⢦⡗⠊⢹⠩⠃⣅⡲⠈⠆⢣⠐⠂
       ⠬⠗⠡⠂⣣⡒⠖⡖⠠⠨⡑⡅⠢⣐⢑⣄⡚⡀⠩⠆⢂⠕⢠⡂⡰⢢⠈⡄⣌⠁⠤⠊⠨⣊⢅⡀⠌
     ⡀ ⢜⠉⣲⠒⢯⡰⡬⣎  ⡆⠃ ⠈⠲⠈⢔⠉⡰⠬⡀⠁⢆ ⡬⠡⠨⠱⢀⠳⣀⢕⠒⢓⢘⢈⠥⠆
     ⠐⠐⢕⠽⢨⣶⣣⡲⠲⠢⡔⣂⡳⠠⡰⠸⣏⠡⠠⠂⠴⢀⡠ ⡰ ⠤⡈⢁⢐⠈⡊⢑⢋⡓⣭⡎⣪⡊⡂
        ⠒⠎⠱⣣⣾⣯⡛⢄⢊⠆⢧⢠⠴⣤⣼⡅⢍⢹⠐⢠⠢⠡⠴⡠⢨⢀⠐⡣⢩⣫⣘⠗⡯⠯⢘⠎
        ⠈⠐⠉⠲⢯⠎⢛⡯⣩⣦⡘⡨⢸⠬⡌⠒⣶⣦⢢⡠⢥⣫⣤⢶⡆⠩⢊⣦⣟⡼⢽⣝⢓⠊⠈
             ⠈⠉⠹⢩⢟⠞⢶⣨⠾⢻⣹⡮⠷⡟⡩⡶⢻⡝⡑⠯⣍⣸⢷⢽⣿⣺⡋⡥⠢
                  ⠈⠂⠑⠈⠈ ⠁⠓ ⠐⠈ ⠙ ⢣⢭⢝⢻⢏⣵⠹⠸⢠
                                ⠐⡥⣃⠁ ⠁⠈
                                 ⠃⣣
                                  ⠋⠁
  
@@@
  
                        ⡀ ⡤⣀ ⢀⠠⢀
              ⢀⣀ ⣄⠉⢜⡌⠢⢭⡔⠓⡅⡀⢖⡇⢞⠾⣰⡐⡐ ⣠⡠ ⡀
           ⢠⢀⠑⢝⠧⡺⣵⢽⣁⢔⡾⠕⠖⢂⢠⠙⢴⣈⠈⢁⠌⢶⠢⢾⠰⣄⠔⠃⠐⠂⢀⠠
        ⢀⠰⢺⡇⡐⠸⡂⢟⢲⢩⠰⠉⠁⠕⡀⣔⠽⠂⠈⠧⣵⠂⠈⠪⠪⡑⡙⡸⠁⠖⡌⢂⡐
        ⠕⠇⠅⢘⢴⢊⡠⠜⣥⢇ ⠄⢔⡑⠂⢙⢂⣄⢂⢐⠨⡆⠊⠣⣄⢙⠄⠜⡨⠉⡅⢈⣝⡄⠅
      ⢀⠐⠅⣜⡜⢤⣗⠢⣁⢢⠎⠂⡸⠠⡢⡋⠠⠐⢃⠉⢆⠠⡌⠤⠤⠥⢨⡒⣅⢜⠂⢓⡂⠊⠉⣲⠡⠂
       ⠂⠇⡍⣣⠗⡴⣆⣰⡑⠲⠌⡂⢃⠆ ⢰⠠⣡⠡ ⠖⠠⣀⠥⠐⡌⠸⠅⢘⡈⠂⢎⡙⣷⣻⣑⡀
          ⢚⣶⣷⣸⡿⠟⠎⠴⡒⡬⣣⡉⡤⣔⡀⠆⠡⢑⡅⠁⢤⢢⠇⠌⣙⣁⡸⠏⠽⢮⠏⢱⠔
         ⠁⠑ ⠾⡝⡛⣯⢧⢯⢇⣤⢅⠞⡜⡠⢆⡭⡡⣦⢠⣊⠍⡸⣴⣿⣅⢥⠿⠟⡳⢛⡗⠋
             ⠈⠙⠸⠘⠣⢣⢶⠟⡃⣧⣝⣟⠗⣽⡎⣳⠚⢭⣽⣨⡺⣯⢮⣽⡫⡟⢹⠴
                  ⠈ ⠑⠈⠂⠉⠐⠘⠐⠁ ⠘⠈⢰⠭⣝⣾⣮⠜⡋⠄⢡
                               ⠐⡧⣑⠁ ⠁ ⠁
                                ⠑⢪
                                 ⠋⠁
  
@@@
  
                       ⢀⠠⢀⢀⠠⡀ ⢀⠄⢀
               ⢀⡀⡠⡈⠨⣉⣥⡷⠢⣛⠸⣉⠔⢧⢰⢆⢱⢀⢀⢐⢠⠄⡀
            ⢀⢔⡐⠵⡭⣿⢅⢻⣶⡖⠤⣪⠲⢀⡊⡡⣋⢔⡅⡰⣦⠎⣤⣔⠪⠆⠐⢀⠠
          ⠐⡝⢶⠈⢲⣒⠎⠖⡭⠰⢠⡄⠍⠁⢳⣃⣔⠓⠡⡷⠺⡙⡨⠫⠶⢛⠱⢾⢒
          ⠕⠌⡓⠰⣸⠺⣇⣑⢴⢵⠒⠃⢤ ⠐⣊⠰⣢⣑⡀⠁⠸⠕⠚⣍⢆⡬⡀⠌⣽⢄
        ⠐⢨⠄⡰⡵⡈⡅⡚⠖⠁⣸⡦⠘⢂⠡⡳⠤⠁⠤⠢⢡⡑⠂⡰⡀⠨⢔⠌⠝⠐⣡⡊⢻⠢
          ⢟⣯⢣⣶⠑⡎⢖⣱ ⡒⠦⢔⡆⢖⠂⢀⣜⡈⡎⠝⠰⠁⢯ ⠦⡬⢀⡒⢠⢟⣟⡀⢁
          ⢀⢚⣞⣿⣲⣤⢴⡾⣿⢠⢵⢐⠢⢡⠰⢈⢤⣂⡰⠨⠉⣑⡡⡽⠮⠜⢀⡺⡥⢝⡼
           ⠑⠸⠛⢼⡝⣟⡎⢬⠡⣞⢇⣪⢼⠄⢉⣣⣈⡑⠼⣇⡬⣤⣽⣺⢇⣾⠋⡝⣚⠢
             ⠈⠑⠜⠏⠜⠕⢚⠆⣻⢮⡿⣓⣿⣿⣿⣧⠪⢳⣹⢽⣮⡧⡿⣝⠙⡥⠂
                   ⠁⠈⠈⠂⠁⠓⠚⠈ ⠂ ⢯⢴⣟⡷⡵⠏⡦⢁⠄
                              ⠪⣎⡊ ⠈ ⠁
                              ⠈⠂⣏
                               ⠘⠉
  
@@@
  
                      ⢀⣠   ⡀⠄⡀⢠⠄ ⡀
                 ⢀⣄⣁⠩⣬⠿⣁⡒⡯⠱⡵⣂⠢⠺⣠⢐⣀⢰⡄
              ⢀⣲⣈⠾⢯⡺⣒⠁⠗⣠⡎⠙⣨⠰⠁⡴⣸⢖⠥⣔⢘⠰⢶⠠
            ⠘⠅⣾⢰⡺⠷⢣⣠⠑⡺⠡⣲⡆⢨⠿⢑⡈⡳⠸⠖⠧⠘⢜⢳⣟⢄
             ⡗⣰⠵⣹⠙⠄⠱⣌⢠⣰⡴⢊⡆⠈⠑⠹⠂⣙⣃⡀⠘⠌⢲⢯⢴⡁⡀
           ⠢⢡⣤⢴⡫⠋⢧⠈⣚⠳⠅⣣⠤⢢⠡⣒⣆⡀⠈⠚ ⡉⡀⠄⢨⡽⢹⢃⡌⠂
            ⢵⣼⣰⣱⠇⠐⠢⣰⡖⡖⡐⣪⡒⢋⠔⢙⠑⠄⡂⡩⠄⠒⢤⠄⡿⣵⢈⣖⣉⡀
           ⢈⣲⡖⡗⣾⣇⣥⣦⠖⡰⠿⠋⢢⣘⠸⠈⣘⣀⣥⡏⠘⠬⠈⢝⡯⡽⢭⡣⡔⠁
            ⠂⠩⠋⠿⢫⡿⣵⣮⣳⢭⠝⣎⣍⡉⢒⢏⣨⣤⣱⡿⣦⣡⢝⣿⠿⢗⢚⠠
             ⠈ ⠲⠹⠹⠝⠛⡟⢷⡙⣛⡏⣬⡷⣾⣽⡿⢿⣷⢿⣯⣟⣫⠟
                    ⠁⠈ ⠑⠓⠁⠐⠃⠵⣝⣯⠟⡟⠩⡪⡡
                            ⠸⢴⡃⠁⠁ ⠁
                             ⠑⢯
                              ⠋
  
@@@
  
                      ⣠    ⢀⠠⢀⢤  ⢀
                  ⡀⢨⣸⡸⡈⢅⠆⢍⣔⠿⢻⡒⠣⡄⣀⡖⠐
              ⢀⣠⢘⢔⢺⠿⣫⢢⡋⠑⡸⡡⢮⡢⡀⡶⢥⣦⡣⣦⠶⠤⠆
              ⢀⠧⠥⢳⡟⢮⠖⣲⠲⡩⣂⢙⠽⢴⠈⠘⣕⣓⠙⣺⠝⡣⡊⠂
              ⣒⣆⠵⢫⢭⠡⡒⡎⠠⢙⣬⠣⣹⢘⠆⠂⠊⠐⡈⣣⡨⣶⢺⡀
             ⠤⡞⠹⢍⣬⣾⠕⠥⡈⠒⢞⡐⢨⠰⡅⠊⠥⡐⠈⡙⠪⡘⣲⢞⡄⢣
             ⣱⠹⡣⡳⡮⣴⢳⡘⠋⠑⢘⡰⠐⣺⠣⡐⢖ ⢂⣺⢵⡽⢜⣤⣧⣜⡈
            ⣊⢲⣴⣺⣷⣲⡶⣿⣠⠎⢓⢩⢞⣯⠓⢘⠠⠁⠃⠱⣙⡯⠝⠭⢬⢍⡎
             ⠈⠋⠺⠽⢿⣻⣿⠴⣕⠑⡳⠚⣭⣌⠼⡧⣑⣨⣨⣹⠽⢿⣶⣵⠣
              ⠈ ⠐⠼⠻⠞⢓⣽⢳⡅⡚⢮⣷⣳⣯⣷⢿⣿⣵⢟⠙⠉
                     ⠈⠉⠑⠒⠞⢕⣞⡽⢻⠍⢹⡠⠈
                          ⠨⢦⡋⠈ ⠁
                           ⠑⢏
                           ⠈⠊
  
@@@
  
                    ⢀⠠⣀     ⡀⠤⣄  ⡀
                 ⡀⡀⠣⢀⠦⣅⣭⣕  ⢺⡎⢺⣧⣄ ⡒
              ⢀⡈⣠⡨⣖⡖⢙⣍⡿⢼⣃  ⢲⢿⢧⡐⣲⢴⣮⡠⠔⠄
               ⢄⢠⠮⡙⣷⢺⡧⣧⢿⠏  ⢐⣊⢕⡊⡾⡗⣻⡪⠏⠐⠂
             ⠐⣀⣪⠄⣇⣸⡏⠉⠎⡍⣌⠂  ⢠⢋⡭⢦⠖⡮⠺⡖⣓⣰⡒⠁
             ⠄⠫⢪⣽⡮⠟⣜⣄⡥⡗⡁⠇  ⢘⢘⢌⠼⣶⠄⣓⡸⡎⣠⣠ ⠠
             ⠑⣀⠽⣲⡎⢋⢻⠄⡪⡋⡸⠒  ⣐⣣⢷⢇⡓⣔⣢⡓⣅⡯⣯⢤⠄
             ⢂⣾⢾⣷⣾⢕⡘⣓⢬⣷⡳⡫  ⠸⡻⢿⢝⠣⠅⠭⡪⣟⢬⣥⡉⠁
              ⠈⢙⠯⣿⢻⣮⢟⡯⢿⣥⡷⣠⡀⡈⣙⡝⣵⠊⣾⠤⡿⡭⡔
                ⠋⠙⠿⣳⢫⢻⣿⣟⡿⣷⣵⢿⣿⣿⣿⡟⠯⡉⠟⠃
                     ⠸⠈⡻⢧⢟⠶⡹⡽⡈⠘ ⠁
                        ⠨⢢⠋⠈
                         ⠹⣎
                         ⠘⠁
  
@@@
  
                   ⡀ ⠄⡀⡀    ⡠⠤⡀ ⡀
                 ⡀⠂⠨⢨⡮⣼⣌⠨⣗⡄⢒⣮⣗⡝⡥⢲⢂
               ⣀⣁⢰⡣⣩⡂⡗⡚⣬⢫⢾⢯⠎⣰⠊⠶⠳⣖⢰⣮⡠
              ⠄⢜⢄⣿⡾⡹⠟⠙⠗⢖⠒⢠⢔⡊⡢⠥⠂⡸⡿⣓⢿⣾⠒⠄
             ⢰⣀⣠⣹⡷⣉⠄⠣⣉ ⠈ ⡝⠊⡵⢸ ⢩⢠⢦⢽⣞⣒⡶⢖⢈
            ⠠⠨⣮⢷⣝⠉⠒⡧⠁⠨⡠⡝⡡⡉⢼⢎⢂⢐⢐⠐⠒⡧⡫⣎⢚⡄ ⠠
             ⣐⠙⡝⡲⡙⠪⠢⠢⠈⢒⣛⠤⣥⡧⢙⡅⡒⢄⣓⢕⡾⣺⡷⣰⠥⣓⠤
            ⢀⢰⡻⡶⣻⣯⢸⡻⣈ ⡐⣊⡂⣬⢮⠡⡗ ⠄⠞⡿⡝⠤⣦⠼⣪⡥⡌⠁
             ⠉⡀⠯⠷⣓⢮⣟⣷⡯⡄⣉⡙⣪⡹⡓⠶⡒⣄⢺⢏⡥⠏⣞⠧⠁
              ⠘ ⠊⠁⡋⢻⡾⣾⣿⢿⡿⣿⡿⣝⣧⡬⣻⡼⡽⠜⠫⡴⠃
                  ⠢⠘⡸⢵⡒⣿⡿⠝⡉⠈⠉⠊⠁ ⠂
                      ⠨⣾⠑
                       ⢽⡁
                       ⠙
  
@@@
  
                  ⢀  ⠄⡀⢀   ⠤⡀⡄⣀
                 ⣐ ⠄⣵⡜⡠⣔⠨⢪⢿⣳⣔⡬⠦⢝⠓⢄⠰⡀
              ⢀⡈⣈⣉⢞⡄⡭⣔⠞⢳⣗⣼⡃⠽⣗⣟⠦⢣⠦⢪⣮⡦ ⢤
             ⡀⠼⢇⢼⠯⠊⣓⠅⢳⢑⠘⠗⠕⢫⠆⡦⢼⠰⢜⡈⠱⣍⠷⣣⡚⠁⠄
           ⠠⣀ ⢹⡍⣞⢁⠔⢕⠠⡅⠁⢼⠐⣄⢀⠩ ⠤⠲⣃⠖⠉⡨⣐⣾⠷⣘⡂⠄
           ⠦⣬⢻⡿⡟⠛⢇⠉⡊⠜⠈⡡⢂⠈⣄⠦⢐⠢⢋⢢⠎⣘ ⡀⢂⣷⣚⢦⢌
          ⠐⡉⢘⢉⠙⠆⡇⠅⣐⢇⠱⡧⠧⡐⠡⡈⢲⣙⡥⣄⣈⠝⣏⠠⠂⠦⣲⣺⢶⢱⡤
           ⢘⡰⢱⡳⠿⣴⢗⣵⣹⡘⠼⣮⢇⡅⡀⡐⢖⢰⣼⠉⢭⠑⡦⠎⡭⢧⠞⣻⢹⠅
           ⠈⠁⠑⡈⠷⡾⣵⣓⣾⣯⣕⣽⢗⠚⢧⠹⡹⠟⣍⣾⠴⢌⢴⣸⣛⣭⠁⠨
              ⠓⠁⢉⡷⢻⣷⣿⣿⣿⡿⢻⢋⣾⠿⡯⣩⠫⣆⣹⡞⢏⠨⡧⠂
               ⠐⠮⢩⢂⢮⢺⣿⣶ ⠛⠉⠁⠁⠉⠉⠐  ⠂
                    ⠠⣽⠐
                     ⢼⡃
                     ⠙
  
@@@
  
                  ⡀  ⠄ ⡀⡀ ⠤⢀⡀⣄
                 ⡐⢄⢸⡨⡅⣣⣠⣄⢊⣦⠾⠧⢬⠲⣎⣉⡂⠅⠰ ⡀
            ⡀ ⢀ ⣍⢄⣓⣽⠒⢧⢶⢔⠖⢔⢚⡥⠞⠽⣇⢾⣷⡴⡧⢌⡰⠢ ⢠
           ⢠⠈⢰⢿⠟⣷⢽⡻⡀ ⠃⡌⠰⢝⠨⠂⡃⠒⢏⠠⠟⠜⠞⢼⢖⣊⡮⢫⠘⣢
          ⠠⢈⡹⠉⠁⠱⣰⡁⢉⠤⡐⡦⡂⡈⠬ ⡭⠆⢄⡀⠂⢀⠡⡀⡒⢻⠦⢣⢲⠚⠸⡂⠠
         ⠂⢥⣽⢒⠯⠘⣜⠍⠍⠣⣂⠈⢀⠐⠐⢑⢈⠆⠊⡤⡅⢥⡀⠌⢊⢬⢪⢃⠢⢴⡒⢄⡉⠄
         ⠋⡉⠙⡑⡡⡂⠳⢀⠧⠽⡑⠘⣠⣠⢓⣃ ⡄⢁⠸⡙⠒⣭⢤⡄⡠⡣⣩⢺⢶⡕⡦⣒⠆
         ⠈⣸⣙⡼⠣⡲⢈⠮⢘⢹⣭⡖⠔⢠⡠⠸⡂⡩⣫⣀⡁⣒⣦⢠⡦⢅⡅⢻⣝⡯⠨⡷⠚⠈
           ⠉⠃⠻⡿⢮⣦⣅⣜⣑⢟⡾⣴⣱⢦⠣⡚⡊⣭⢭⡪⠿⣃⣗⡼⢪⡼⣩⠊⠭⠁
             ⠐⢻⢾⢾⣿⣿⡻⣯⣗⠙⢹⣷⠾⢎⣯⠻⣷⡯⢕⢜⡏⢘⠳⣄⠃⠄
             ⠘⠤⢡⢢⣸⠯⣗⣷⠈⠊⠁⠙⠋⠈ ⠉⠈  ⠂ ⠂
                  ⠉⣼⡇⠂
                   ⢼⣑
                   ⠙
  
@@@
  
                  ⢀  ⠠ ⢀⢠⠄⢀⣀⠠⡀
                 ⡄⣒⠌⣵⣄⠭⣂⣸⣶⠘⠤⠴⠽⠆⣨⠉⣐⣄⠁⠔ ⡀
           ⡀⢠⡀ ⡂⢌⣳⢛⠬⢳⡦⡄⠔⣀⡦⠒⡶⣑⣕⠎⢳⣇⢷⡭⣐⣬⠥⠒ ⢠
          ⠄⡉⢲⣮⠠⡳⣻⠎⠕⡬⠄⢎⠠ ⢸⠁⠚⠥⠁⠛⠚⠺⢪⠮⢳⠖⣢⡑⡦⣩⠲⠄⢂⡀
         ⡀⡩⣫⡉⠄⡁⠸⢄⠖⡄⡊⢉⠌⢄⠄⠆⣢⠠⠂⢁⡡⢺ ⢂⠢⡜⡘⠐⣒⡞⢡⢞⠘⢰⠥
        ⠱⢨⢊⢿⡠⠩⠭⠐⡔⡉⡅⠑⠆⡔⠁⠃⠐⢠⠫⠁⡀⡠⢈⡠⠄⠠⣠⢍⠂⣪⠰⡗⡔⢖⢁⡈⠄
        ⠙⠊⣒⠻⢂⣈⠍⢦⠂⢅⣀⠦⡓⡊⢀⠃⢨⡂⣋⠂⠠⠤⠠ ⢄⠃⣎⣸⢬⣠⠿⢾⡓⣀⣲⡒⠆
         ⡍⢸⡚⢑⡬⠞⢺⠧⠐⠤⡐⠸⣮⡡⠳⠌⡢⣈⣀⠇⠄⣌⣪⡀⡔⡆⡍⡯⣲⡫⢹⠇⠐⠊⠖⠁
          ⠁⠛⠩⡼⢾⣩⣏⢿⣂⣴⡶⢔⣎⢫⠬⣦⡸⡤⡽⣧⢒⣪⣕⠵⢅⣫⢴⣽⢭⠩⠫⠈
           ⠐⠠⡰⠿⣿⣿⣮⣿⡿⡋⢖⡌⡺⡣⡽⠷⣺⢽⡼⡫⢶⡎⢍⠃⢭⢖⡈⠠
           ⠈⠢⠡⢇⡗⡿⣻⢔⢼⠊⠁⠋⠉⠐⠊ ⠉⠈⠈⠁  ⠂⠂
               ⠈⠈⢀⡯⡂⠂
                 ⠠⢝⡃
                 ⠈⠑
  
@@@
  
                   ⡀  ⠄⠠⢀⣀ ⡠⡀
               ⡀ ⢄⡆⣖⢡⠠⡀⡕⢗⡒⢴⠜⠤⠅⣋⠭⠁⡐⣄⣈⢆ ⢀
          ⢄ ⡐ ⠘⡰⡆⡕⠍⣴⠂⠒⠱⣀⢲⠤⣐⡰⣤⢒⣻⡞⣟⢡⠦⢻⠧⣈⠈⠢⢠
         ⠄⠘⢢⣰⣚⠔⠸⠝⢗⢦⠼⠄⡁⡎⠈⠂⠄⠈⢅⠒⠣⠭⠑⠖⢑⢐⠎⡉⠶⠣⣽⠸⡂⡰⢐⡀
        ⡀⢉⠨⢣⡁⢅⠘⡄⡰⢁⠢⠈⡠⢸⢈⡄⠰⢀⡀⠦⡑⠆⠘⡯⢌⢚⠂⣀⢒ ⠔⡀⣾⢂⠻⡠⠡
      ⠠⠁⠐⢑⣼⢹⠢⡂⠥⡨⠒⠠⢊⡃⠎⠙⡰⢥⠘⢈  ⡠⠊ ⠄⣄⢍⠰⠄⠠⡠⢕⠁⣜⡺⢗ ⡠⡁
       ⠑⢙⠙⢪⡮⢕⠖⣈⡠⢑⡓⣀⡌⡀⢳ ⢀⠙⠠⠆⠠⢄⣃⠔⡄⠠⠦⠨⣴⠫⠵⡞⣴⢖⢇⢏⣰⠒⠆
       ⠈⠨⢙⣿⣚⣛⡯⢠⠄⠐⠴⡊⠰⠡⡘ ⢽⣅⠠⠦⢂⠸⢠⡰⠢⠉⣍⢹⣔⣶⣢⣾⢫⠩⠕⠓⠂⠕
          ⠃⠉⣾⡟⣟⣗⣨⡴⢻⠬⣀⠂⡧⢠⡶⡨⠎⣤⣖⡎⣬⠖⠅⣚⠹⣕⢛⣙⢭⠝⠪⠃⠈
          ⠂⠤⡰⣿⣿⢿⣯⣿⡬⡛⢒⠻⣜⠠⡟⢙⢺⢜⠼⡼⡾⡮⠻⣫⠯⢋⠎⡃⠄
          ⠈⠢⢣⢯⡞⢜⢫⢐⠡⡎⠃⠉⠙  ⠒⠁ ⠉ ⠉⠈ ⠒
             ⠈ ⠁ ⣱⢕⠂
                 ⢝⡑
                 ⠙
  
@@@
  
  
                     ⠄⡀ ⢀⢤ ⢀
             ⢀ ⢄⢄ ⢂⢂⡆⠷⡲⢜⣒⡄⢨⠖⢩⡭⠴⠨⡣⠉⣠ ⣀⣀
         ⠄⡀⠐⠂⠘⠢⣤⠄⡷⢔⠖⠤⡁⢁⢁⢔⠋⡠⡀⠲⠸⢦⡂⡈⡯⣮⡕⡴⠫⠂⢀⡄
          ⠐⢂⡐⢡⠲⠁⢇⠛⢘⠗⠅⠁⢒⡧⠺⠃⠐⠯⡢⢀⡎ ⠁⠧⢨⠔⡿⢐⠳ ⡱⡇⠆⡀
         ⠡⢠⣫⡁⢨⠁⠹⠤⠠⡃⡠⡜⠈⡢⢎⠂⢀⢆⣀⢋⠐⢁⡢ ⢄⠕⢾⠲⢀⡐⢢⡐⠨⠘⠎
        ⠐⠬⣒⠉⠁⢐⢓⢐⢥⡸⠪⣀⠅⠄⠄⢥ ⢊⠈⡑⠂ ⢃⠔⡠⠃⠐⠣⢔⢀⠔⣺⡤⢣⡣⡠⠂⡀
        ⢐⣡⢛⢆⠃⡕⠘⢈⢃⠘⠬⣠⠂⠨⣀⠄⠐⠄⠬⣨⠄⡄ ⠰⢑⠚⡠⠐⢃⠆⣰⢲⡺⣔⠋⡼⠐
         ⠲⡍⠹⡽⠬⠸⢆⣑⣉⠠⢺⠢⢠ ⢅⠣⠡⠐⠄⣢⠤⡈⢕⠬⣒⠆⠸⠙⢧⣧⣷⣶⡓⠂
          ⠑⢸⡓⢞⠺⢽⡨⣥⣷⡠⠺⡨⣆⣠⠠⣇⢍⡰⢄⢪⠺⡨⡄⢪⢽⡼⣝⠙⢫⠵⠂⠂⠉
           ⠤⡗⢽⢙⣮⢿⢼⡓⣥⣪⡨⠓⣌⣹⣝⠽⡻⣪⣦⢙⠻⢶⢾⠜⠃⠅⠋⠁
            ⡌⠬⢛⢧⣳⣷⢩⠩⡆⠁⠊ ⠈⠂⠃⠂⠉⠐⠁⠘ ⠁
             ⠈ ⠈ ⠈⣊⢼⠂
                 ⠠⡇⠊
                 ⠈⠙
@@@
  
  
  
                     ⠄⡀ ⢀⢄ ⢀
             ⢀ ⢄⢄  ⢂⡆⠗⡒⢜⢒⡄⢨⠖⢨⡥⠔⠨⡣⠉⡠ ⣀⣀
         ⠄⡀⠐ ⠐⠢⣤⠄⠵⢔⠖⠄⡁⢁⢁⢔⠉⡀⡀⠲⠸⢦⡂⡈⡯⡮⠕⡐⠫⠂⢀⡄
           ⢂⡐⢡⠲⠁⢇⠛⢘⠗⠅⠁⢂⠧⠺⠃⠐⠯⡢⢀⠌ ⠁⠧⢈⠔⠿⢐⠳ ⡱⡇⠆⡀
         ⠡⢠⣩⠁⢈⠁⠱⠠ ⡃⡠⡈⠈⡂⢎ ⢀⢆⣀⢉⠐⢁⡢ ⠄⠕⢾⠲⢀⡐⢢⡐⠨ ⠌
        ⠐⠬⣂⠉⠁⢐⢓⢐⢁⡸⠊⣀⠅⠄⠄⢥ ⢊⠈⡑⠂ ⠃⠔⡠⠃⠐⠣⢄⢀⠔⣺⡤⢃⡣⡠⠂⡀
        ⢐⣡⢛⢆⠃⡅⠘⢈⢃⠘⠌⣠⠂⠨⣀⠄⠐⠄⠬⣨⠄⡄ ⠰⢑⠚⡠⠐⢃⠆⢀⢲⡺⣔⠊⡼⠐
         ⠰⡍⠹⡵⠬⠸⢂⣑⣉⠠⢺⠢⢠ ⢅⠣⠡⠐⠄⣢⠤⡈⠕⠬⡒⠆⠸⠙⢧⣧⣧⣶⡑⠂
          ⠑⢸⡓⢞⠺⢽⡨⣤⣷⡠⠺⡨⣆⣠⠠⣅⢍⡰⢄⢪⠺⡨⡄⢪⢹⠼⣝⠉⢉⠵ ⠂⠁
           ⠤⡕⢽⢙⢮⢼⢸⡓⣥⡪⡨⠓⣌⣹⣝⠽⡻⣪⣆⢙⠪⢶⢼⠜⠁⠅⠋⠁
            ⡄⠬⢛⢣⣳⣷⢩⠩⡆⠁⠊ ⠈⠂⠃⠂⠉⠐⠁⠘ ⠁
               ⠈ ⠈⣊⠼
                 ⠠⡇⠊
@@@
  
  
  
  
                     ⠄⡀ ⢀⢄ ⢀
             ⢀ ⢀⢄  ⢀⡆⠆⡒⠜⢒⡄⠨⠖⢨⠥⠔⠨⡠⠉⡀ ⣀⣀
         ⠄⡀⠐ ⠐⠢⣤⠄⠵⢔⠒ ⠁⢀⢁⠐⠁⡀⡀⠲⠸⢦⡂⡈⡯⠮⠕⡐⠫⠂⢀⠄
           ⢂⡐⢡⠲⠁⢆⠋⢘⠗⠄⠁⢂⠧⠺⠁⠐⠧⡢⢀⠌ ⠁⠥⢈⠔⠹⢐⠳ ⡰⡃⠆⡀
         ⠡⢠⣉⠁⢈⠁⠱  ⡃⡠⡈ ⡂⢎ ⢀⢆⣀⢉⠐⢁⡀ ⠄⠕⢾⠠⢀⡐⢢⡐⠨ ⠌
        ⠐⠌⣂⠉⠁ ⢓⢐⢁⡨⠊⣀⠅ ⠄⠥ ⢊⠈⡑⠂ ⠃⠔⡠ ⠐⠣⢄⢀⠔⣚⡄⠁⡣⡠⠂⡀
        ⢐⣡⢛⢆⠃⡅⠈⢈⢃⠘⠌⣠⠂⠨⣀⠄⠐ ⠬⣨⠄⡄ ⠰⢑⠚⠠⠐⢃⠆⢀⢲⡲⣄⠊⡼
         ⠰⡌⠩⠵⠤⠸⢂⣑⣉⠠⠺⠢⢠ ⢅⠣⠡⠐⠄⣢⠤⡈⠕⠬⡒⠄⠨⠙⢧⣇⣧⣶⡑⠂
          ⠑⠸⡓⢖⠺⢽⡨⢤⣵⡠⠺⡠⣆⢀ ⣅⢍⡰⢀⢪⠺⡨⡄⢪⠹⠼⣝⠉⢉⠵ ⠂
           ⠤⡕⢝⢙⢎⢼⢰⡑⠥⡪⡨⠓⣌⢹⣝⠍⡻⣪⡆⢑⠪⢖⢴⠜⠁⠅⠃⠁
            ⠄⠤⢛⢣⣳⣧⢩⠩⡆⠁⠊ ⠈⠂⠃ ⠉⠐⠁⠐ ⠁
               ⠈ ⠈⢊⠼
@@@
  
  
  
  
  
                        ⢀⢄ ⢀
               ⢀⢄  ⢀⡆⠆⠂⠜⢒⡄⠨⠒⢨⠡⠔⠨⡠⠉  ⢀⣀
         ⠄⡀⠐ ⠐⠢⣤ ⠥⢔⠒  ⢀⢁⠐⠁ ⡀⠲⠸⠆⡂⡀⡭⠮⠕⠐⠣⠂⢀
           ⢀⡐⢡⠲⠁⢄⠋⢘⠗ ⠁⠂⠧⠺⠁⠐⠧⡂⢀⠌ ⠁⠥⢈⠐⠸⢐⠳ ⡐⡃⠆⡀
         ⠡⠠⣉⠁⢈⠁⠡  ⡃⡠⡈ ⡂⠆ ⢀⢂ ⢈⠐⢁⡀ ⠄⠕⢾⠠⢀⡐⢢⡐⠈ ⠄
        ⠐⠌⣂⠈  ⢓⢐⠁⠨⠂ ⠅  ⠠ ⢊⠈⡑⠂ ⠃⠔⡠ ⠐⠢⢄⢀⠄⣚⡄⠁⡡⡀⠂
        ⢐⣡⢛⢆⠃⠅⠈⢈⢁⠘⠌⢠ ⠨⢀⠄⠐ ⠤⣠⠄⠄ ⠰⢑⠊ ⠐⢃⠆⢀⢲⡲⣄⠊⡜
         ⠰⡌⠨⠱⠤⠸⠂⣁⣉⠠⠺⠢⢠ ⢅⠣⠡⠐⠄⣢⠤⡈⠕⠬⡐⠄⠨⠙⢧⢇⣧⣶⠑⠂
          ⠑⠸⡓⢖⠺⢽⡨⢠⡵⡠⠺⠠⣆⢀ ⣅⢍⡰⢀⢪⠺⡨⡄⢊⠩⠼⣝⠉⢉⠵ ⠂
           ⠤⡕⢑⠙⢌⢴⠰⡑⠅⠢⡨⠓⣌⢹⣙⠌⡺⣪⡆⢐⠊⢖⢴⠜⠁⠅⠃⠁
            ⠄⠤⢛⢡⡳⣧⠩⠈⠆⠁⠂ ⠈⠂⠃ ⠉⠐⠁⠐
@@@
  
  
  
  
  
  
                        ⢀⢄ ⢀
                ⢄   ⡆⠆⠂⠌⢐⡄⠨⠒⢨⠡⠔⠠⡠⠉  ⢀⢀
         ⠄⡀⠐ ⠐⠠⣤ ⠥⢔⠐  ⢀⢁   ⡀⠲⠰⠆⡂⡀⡬⠬⠕⠐⠣⠂
           ⢀⡀⢡⠲⠁⢄⠃⢈⠕ ⠁⠂⠧⠲ ⠐⠥⡂ ⠌  ⠡⢈⠐⠸⢀⠒ ⡀⡃⠆⡀
         ⠡⠠⣈⠁⢈⠁⠡  ⡃⠠⡀ ⡂⠂ ⢀⢂ ⢈⠐⢁⡀ ⠄⠕⢔⠠⢀⡐⢂⡀  ⠄
         ⠌⣂   ⢓⢐⠁⠨⠂ ⠅  ⠠ ⢈⠈⡐⠂ ⠃⠔⡠ ⠐⠢⢄ ⠄⣒⡄ ⡡⡀⠂
        ⢀⣡⠋⢆⠃⠄⠈⢈⢀⠈⠈⢠ ⠠⢀⠄⠐ ⠠⢠⠄⠄ ⠰⢑⠂ ⠐⢃⠆⢀⢲⠰⣄⠈⡜
          ⡌⠠⠠⠠⠨⠂⣁⣉⠠⠺ ⢀ ⠅⠣⠠⠐ ⠢⠤⡈⠕⠬ ⠄⠨⠙⢧⢃⣧⣴⠑⠂
          ⠁⠸⡓⢖⠺⢽⡨⢠⡴⡠⠲⠠⢆⢀ ⣄⠅⡐⢀⢨⠸⡨⡄⢈⠡ ⣝⠁⠉⠵ ⠂
           ⠄⡕⢑⠙⢌⢔⠰⡑⠅⠢⠈⠓⣌⠱⣘⠌⡺⣢⡂⢐⠊⢖⢔⠜⠁⠁⠃
@@@
  
  
  
  
  
  
  
                        ⢀⢄ ⢀
                ⢄   ⡆⠆⠂⠌⢀⡀⠨⠐⢠⠡⠄⠠⡠⠁  ⢀⢀
          ⡀⠐ ⠐⠠⣄ ⠥⢔⠐  ⢀⢁    ⠲⠰⠆⡂⡀⡌⠄⠅⠐⠂⠂
           ⢀⡀⢠⠲⠁⢄⠃⠈⠕ ⠁ ⠧⠰ ⠐⠤⡂ ⠌   ⠈⠐⠸⢀⠒ ⡀⡃⠆⡀
         ⠡⠠⢈⠁⢈⠁⠁  ⡁⠠  ⡂⠂ ⢀⢂ ⢈⠐⢀⡀ ⠄⠅⢄ ⢀⠐⢂   ⠄
         ⠌⣂   ⠓⠐ ⠠⠂ ⠅  ⠠ ⢈ ⡀⠂ ⠃⠔⡠ ⠐⠂⠄ ⠄⣐⠄ ⡁⡀⠂
         ⣡⠋⢆⠃⠄⠈⢈ ⠈⠈⢀ ⠠ ⠄⠐  ⢀ ⠄ ⠰⢁⠂ ⠐⢃⠆⢀⠲⠠⢄⠈⡌
          ⡌⠠ ⠠⠨⠂⣁⡈ ⠂   ⠅⠃⠠⠐ ⠢⠤⡀⠕⠤ ⠄⠨⠙⢃⢃⣥⢤⠑⠂
          ⠁⠸⡒⢖⠰⢼⡈⢀⡰⡠⠲⠠⢆⢀ ⣄⠁⡀⢀⢈⠨⠨⡄⠈⠡ ⣝ ⠈⠠ ⠂
@@@
  
  
  
  
  
  
  
  
                        ⢀⠄ ⢀
                ⠄   ⡂⠂ ⠄ ⡀⠨⠐⢠⠡ ⠠⡀⠁
           ⠐ ⠐⠠⣄ ⠅⠔    ⢀     ⠠⠂⠂⡀⡀⠄⠄⠐⠂
           ⢀ ⢀⠲ ⢀⠁⠈⠕ ⠁ ⠂⠰ ⠐⠤⡀ ⠄   ⠈⠐  ⠒ ⡀⡀⠆
          ⠠⢈⠁⢈⠁⠁  ⠁⠠  ⡂⠂ ⢀⢂ ⢀⠐⢀   ⠄⢄ ⢀⠐⠂   ⠄
         ⠌⣂   ⠓⠐  ⠂ ⠅  ⠠ ⢈  ⠂ ⠃⠔⡠ ⠐⠂  ⠄⣀  ⠁⡀⠂
         ⡁⠉⠂⠃⠄⠈⢀ ⠈⠈⢀ ⠠ ⠄   ⢀ ⠄ ⠰⠁⠂ ⠐⠃⠄ ⠲⠠⠄ ⠌
          ⡌⠠  ⠈⠂⡁⡀     ⠄⠁ ⠐ ⠠⠤ ⠕⠤  ⠨⠑⠃⢀⢠⢄⠑⠂
@@@
  
  
  
  
  
  
  
  
  
  
                    ⡂⠂   ⡀⠨⠐⢀⠠ ⠠ ⠁
           ⠐ ⠐ ⣀  ⠔    ⢀     ⠠⠂ ⡀    ⠂
              ⠐  ⠁⠈⠐ ⠁  ⠐ ⠐⠤       ⠐  ⠒ ⡀
           ⢈⠁⢈    ⠁    ⠂ ⢀⠂  ⠐     ⢀ ⢀     ⠄
         ⠄⣂   ⠐⠐    ⠁    ⠈  ⠂  ⠄⡠ ⠐⠂   ⡀    ⠂
         ⠁⠈⠂⠂ ⠈    ⢀       ⢀   ⠠⠁⠂ ⠐⠂  ⠒   ⠈
@@@
  
  
  
BRAIN
)
printf '%b' "$M"
printf '%s\n' "$_anim" | while IFS= read -r _l; do
  if [ "$_l" = "@@@" ]; then slp 0.085; printf '\033[H'; else printf '%s\033[K\n' "$_l"; fi
done
printf '\033[2J\033[H'   # audit-ok: intro animation starts from a clean screen
while IFS= read -r _l; do printf '%s\n' "$_l"; slp 0.06; done <<'LOGO'
                          _   ____            _       
    __ _  __ _  ___ _ __ | |_| __ ) _ __ __ _(_)_ __  
   / _` |/ _` |/ _ \ '_ \| __|  _ \| '__/ _` | | '_ \ 
  | (_| | (_| |  __/ | | | |_| |_) | | | (_| | | | | |
   \__,_|\__, |\___|_| |_|\__|____/|_|  \__,_|_|_| |_|
         |___/                                        
LOGO
printf '\033[?25h%b' "$N"
printf '\n'
printf '  '; type_ "one brain · many agents." 0.02
# Header version: serve-lan injects AB_VERSION; the public path (site redirect
# → raw GitHub) has no env, so derive the newest release tag from the repo —
# best-effort with a hard 3s cap, silently blank when offline.
if [ -z "${AB_VERSION:-}" ] && command -v git >/dev/null 2>&1; then
  _vt="$(mktemp -t ab-ver.XXXXXX)"
  GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$REPO" 'refs/tags/v*' >"$_vt" 2>/dev/null &
  _vp=$!
  for _ in 1 2 3 4 5 6; do kill -0 "$_vp" 2>/dev/null || break; slp 0.5; done
  kill "$_vp" 2>/dev/null || true
  wait "$_vp" 2>/dev/null || true
  AB_VERSION="$(awk -F/ '{print $NF}' "$_vt" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | sed 's/^v//' || true)"
  rm -f "$_vt"
fi
# The installer carries its own version. When the target is a prerelease
# candidate (…-prerelease-N), the installer is shown as an rc of the same
# maturity (v0.1.1-rc.N) — it is corrected with every candidate.
_AB_RC=""
case "${AB_VERSION:-}" in *-prerelease-[0-9]*) _AB_RC="-rc.${AB_VERSION##*-prerelease-}" ;; esac
ln_ "  ${D}installer v${INSTALLER_VERSION}${_AB_RC}${N}"
[ -n "${AB_VERSION:-}" ] && ln_ "  ${D}target agentBrain v${AB_VERSION}${N}"
ln_ "  ${D}host: $(hostname) · $(date '+%Y-%m-%d %H:%M %Z')${N}"
printf '\n'; slp 0.15

ln_ "  ${B}Scanning your machine…${N}"; slp 0.15
OS="$(uname)"
# Load user-scoped tool locations before scanning — installed-but-not-on-PATH
# (brew shellenv not yet in the rc, bun/uv from an earlier run) must show as detected.
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
fi
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ] && ! command -v node >/dev/null 2>&1; then
  set +u
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
  set -u 2>/dev/null || true
fi
case ":$PATH:" in *":$HOME/.bun/bin:"*) ;; *) [ -d "$HOME/.bun/bin" ] && PATH="$HOME/.bun/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;; esac
row() { printf '    %b%s%b %-13s %b%s%b\n' "$2" "$1" "$N" "$3" "$D" "${4:-}" "$N"; slp 0.09; }

# Platform first, then the tools that platform actually has. Listing Homebrew on
# WSL is worse than saying nothing: it names something the machine cannot have,
# in a report that reads as authoritative. This mirrors check-prerequisites.sh;
# install.sh is served standalone over HTTP and cannot source it, so the copy is
# deliberate and test-guarded.
PLATFORM="other"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then PLATFORM="wsl"; else PLATFORM="linux"; fi ;;
esac
PM=""
case "$PLATFORM" in
  macos) command -v brew >/dev/null 2>&1 && PM="brew" ;;
  linux|wsl) for _c in apt-get dnf pacman zypper apk; do
      command -v "$_c" >/dev/null 2>&1 && { PM="$_c"; break; }
    done ;;
esac
pkg_hint() {
  case "$PM" in
    brew) echo "brew install $1" ;;
    apt-get) echo "sudo apt-get install -y $1" ;;
    dnf) echo "sudo dnf install -y $1" ;;
    pacman) echo "sudo pacman -S --needed $1" ;;
    zypper) echo "sudo zypper install -y $1" ;;
    apk) echo "sudo apk add $1" ;;
    "") case "$PLATFORM" in
          macos) echo "install Homebrew (https://brew.sh), then: brew install $1" ;;
          *)     echo "install $1 with your package manager" ;;
        esac ;;
  esac
}
req=0
if [ "$PLATFORM" = macos ]; then
  if xcode-select -p >/dev/null 2>&1; then row "✓" "$G" "Xcode CLT"; else row "✗" "$R" "Xcode CLT" "xcode-select --install"; req=1; fi
fi
if command -v git >/dev/null 2>&1; then row "✓" "$G" "git" "$(git --version | awk '{print $3}')"; else
  if [ "$PLATFORM" = macos ]; then row "✗" "$R" "git" "xcode-select --install"
  else row "✗" "$R" "git" "$(pkg_hint git)"; fi
  req=1
fi
if command -v python3 >/dev/null 2>&1; then row "✓" "$G" "python3" "$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"; else row "✗" "$R" "python3" "$(pkg_hint python3)"; req=1; fi
tools="node:node bun:bun jq:jq"
# An explicit if, not "[ ... ] && ...": under set -e that idiom is a known
# footgun when it ends up last in a list, and an installer that aborts halfway
# is expensive to debug from the other end of a LAN.
if [ "$PLATFORM" = macos ]; then tools="Homebrew:brew $tools"; fi
# shellcheck disable=SC2086  # word splitting is the iteration here
for pair in $tools; do
  lbl="${pair%%:*}"; cmd="${pair##*:}"
  if command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in node) v="$(node -v)";; bun) v="$(bun --version)";; jq) v="$(jq --version | sed 's/jq-//')";; brew) v="$(brew --version | head -1 | awk '{print $2}')";; *) v="";; esac
    row "✓" "$G" "$lbl" "$v"
  else row "⚠" "$Y" "$lbl" "will be installed"; fi
done
printf '\n'

if [ "$req" -ne 0 ]; then
  ln_ "  ${R}${B}Missing a required tool.${N} Install the ✗ item(s) above, then re-run."
  if [ "$PLATFORM" = macos ] && ! xcode-select -p >/dev/null 2>&1; then
    ln_ "  ${D}Opening the macOS Command Line Tools installer…${N}"; xcode-select --install 2>/dev/null || true
  fi
  exit 1
fi
ln_ "  ${G}Ready.${N} ${D}Recommended tools marked ⚠ will be offered during setup.${N}"; printf '\n'

if [ "${AB_DRYRUN:-}" = "1" ]; then ln_ "  ${D}(dry-run — stopping before the install prompt)${N}"; exit 0; fi

# An existing checkout makes this an update, not an install — say so, and let a
# decline still reach the personalization (the usual reason to re-run the curl
# on an already-installed machine).
ALREADY=0; [ -d "$DEST/.git" ] && ALREADY=1
ans=""
if [ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ]; then
  ans="y"
elif has_tty; then
  # The prompt helper renders the question itself — do NOT print it twice.
  ab_prompt_confirm "$( [ "$ALREADY" = 1 ] && printf 'Update the existing agentBrain at %s?' "$DEST" || printf 'Install agentBrain into %s?' "$DEST" )" && ans="y" || ans="n"
else
  ln_ "  ${R}${B}No interactive terminal detected.${N}"
  ln_ "  Run this installer from a real terminal, or explicitly set AGENTBRAIN_ASSUME_YES=1 for automation."
  exit 2
fi
case "${ans:-y}" in [Nn]*)
  if [ "$ALREADY" = 1 ] && [ -f "$DEST/scripts/onboard-wizard.sh" ] && has_tty; then
    ln_ "  ${B}Only personalize it instead?${N} ${D}(2 minutes, no AI needed)${N}"
    printf '  %b[Y/n]%b ' "$D" "$N"
    pz="y"; read -r pz </dev/tty || true
    case "${pz:-y}" in [Nn]*) ln_ "  ${D}Cancelled — nothing changed.${N}"; exit 0;; esac
    bash "$DEST/scripts/onboard-wizard.sh" </dev/tty || true
    exit 0
  fi
  ln_ "  ${D}Cancelled — nothing changed.${N}"; exit 0;; esac
printf '\n'
gm="1"
if [ "${AGENTBRAIN_ASSUME_YES:-}" != "1" ] && has_tty; then
  if ab_prompt_select "How do you want to install?" "guided — explain each step" "quick — minimal output"; then
    [ "$REPLY" = 1 ] && gm=2
  fi
fi
case "${gm:-1}" in 2*) export AGENTBRAIN_EXPLAIN=0;; *) export AGENTBRAIN_EXPLAIN=1;; esac
printf '\n'
expl(){ [ "${AGENTBRAIN_EXPLAIN}" = 1 ] && ln_ "  ${D}\xe2\x84\xb9 $*${N}" || true; }


if [ -n "${AB_BUNDLE:-}" ]; then
  tmpb="$(mktemp -t ab.XXXXXX)"
  ln_ "  ${C}▸${N} downloading agentBrain…"
  curl -fsSL "$AB_BUNDLE" -o "$tmpb"
  if [ -d "$DEST/.git" ]; then
    ln_ "  ${C}▸${N} updating existing checkout…"
    adopt_lineage "$DEST" "$tmpb" "$BRANCH" || ln_ "  ${Y}note:${N} ${D}the checkout cannot name its release after this update (git describe gives a bare hash); run: git -C $DEST fetch --force --tags origin${N}"
  else
    ln_ "  ${C}▸${N} unpacking agentBrain…"; mkdir -p "$(dirname "$DEST")"; git clone -q -b "$BRANCH" "$tmpb" "$DEST"
  fi
  rm -f "$tmpb"
  # A bundle checkout has no usable origin — wire one so pull/channel/updates work.
  if [ -n "${AB_REMOTE:-}" ]; then
    git -C "$DEST" remote remove origin 2>/dev/null || true
    git -C "$DEST" remote add origin "$AB_REMOTE"
    ln_ "  ${D}origin → ${AB_REMOTE} (updates enabled when reachable)${N}"
  else
    ln_ "  ${Y}note:${N} ${D}bundle install has no git remote — set AB_REMOTE (or add origin later) to enable updates${N}"
  fi
else
  if [ -d "$DEST/.git" ]; then
    ln_ "  ${C}▸${N} updating existing checkout…"
    # Update from the installer's source ($REPO — the public repo), NOT the existing
    # checkout's origin: that origin may be a private/LAN remote left by an earlier
    # clone (unreachable off-network → the install fails). The public repo is a
    # rewriting clean snapshot, so reset to the fetched ref rather than ff-merge
    # (unrelated lineage). Re-point origin so later updates/session-checks track the
    # public source too. local/ is gitignored — a hard reset never touches it.
    # --tags: the public repo is a rewriting snapshot, so the checkout's old tags
    # never sit on the new lineage; without the new ones `git describe` yields a
    # bare hash and the checkout cannot say which release it is (test-edge-identity).
    # --force on the tags as well: a checkout that once tracked the private
    # lineage holds a v-tag of the same name on another commit, and a plain
    # --tags fetch then refuses it in silence ("would clobber existing tag").
    if adopt_lineage "$DEST" "$REPO" "$BRANCH"; then
      git -C "$DEST" remote set-url origin "$REPO" 2>/dev/null \
        || git -C "$DEST" remote add origin "$REPO" 2>/dev/null || true
    elif [ "$?" -eq 1 ]; then
      ln_ "  ${Y}note:${N} ${D}the checkout cannot name its release after this update (git describe gives a bare hash); run: git -C $DEST fetch --force --tags origin${N}"
    else
      ln_ "  ${Y}note:${N} ${D}could not reach $REPO — keeping the existing checkout unchanged${N}"
    fi
  else
    ln_ "  ${C}▸${N} cloning agentBrain…"; mkdir -p "$(dirname "$DEST")"; git clone -q --branch "$BRANCH" "$REPO" "$DEST"
  fi
fi
cd "$DEST"
if [ -n "${AB_EXPECTED_VERSION:-}" ] && [ -f VERSION ]; then
  ACTUAL_VERSION="$(tr -d '[:space:]' < VERSION)"
  if [ "$ACTUAL_VERSION" != "$AB_EXPECTED_VERSION" ]; then
    ln_ "  ${R}✗${N} bundle version mismatch: expected ${AB_EXPECTED_VERSION}, got ${ACTUAL_VERSION}"
    ln_ "  ${D}Refusing to continue with a stale LAN bundle.${N}"
    exit 1
  fi
fi
[ -f VERSION ] && ln_ "  ${D}agentBrain ${N}v$(tr -d '[:space:]' < VERSION)${D} · $(git rev-parse --abbrev-ref HEAD 2>/dev/null)@$(git rev-parse --short HEAD 2>/dev/null)${N}"
ln_ "  ${C}▸${N} running the full install…"; printf '\n'
# Per-OS bootstrap scripts (symmetric bootstrap-<os> family, same 4-step
# contract: tools -> brain -> pi -> doctor). Dispatch via platform.sh, the
# single detection source; every step journals to the flow journal (flow.sh)
# so main always knows: which flow, which step, which subflow, what is next.
# shellcheck source=scripts/lib/platform.sh
. scripts/lib/platform.sh
# shellcheck source=scripts/installer/flow.sh
. scripts/installer/flow.sh
flow_init "install-$(platform_id)-$(date -u +%Y%m%d-%H%M%S)"

if has_tty; then
  flow_os="$(platform_os)"
  flow_begin "bootstrap-$flow_os" "4-step contract: tools -> brain -> pi -> doctor"
  rc=0
  case "$flow_os" in
    darwin) bash scripts/installer/bootstrap/macos.sh </dev/tty || rc=$? ;;
    linux)  bash scripts/installer/bootstrap/linux.sh </dev/tty || rc=$? ;;
    *) echo "unsupported platform: $(platform_id)" >&2; exit 1 ;;
  esac
  flow_end "bootstrap-$flow_os" "$rc"
  [ "$rc" -eq 0 ] || exit "$rc"
else
  # SSH/CI has no controlling tty. Run the same setup safely without prompts.
  flow_begin "setup-headless" "AGENTBRAIN_ASSUME_YES"
  rc=0
  AGENTBRAIN_ASSUME_YES=1 AGENTBRAIN_SKIP_PI="${AGENTBRAIN_SKIP_PI:-0}" bash scripts/setup/setup.sh </dev/null || rc=$?
  flow_end "setup-headless" "$rc"
  [ "$rc" -eq 0 ] || exit "$rc"
fi

# Optional devtools (cascaded-config capabilities: mail, container, python).
# The interactive path asks; non-interactive runs decline politely — the
# subscript is re-runnable any time: scripts/setup/setup-devtools.sh <intent>.
if has_tty && [ -f "$DEST/scripts/setup/setup-devtools.sh" ]; then
  ln_ ""
  if ab_prompt_confirm --default no "Set up optional devtools now? (mailpit, container tools, uv)"; then
    bash "$DEST/scripts/setup/setup-devtools.sh" </dev/tty || true
  else
    ln_ "  ${D}Skipped. Later: bash $DEST/scripts/setup/setup-devtools.sh (intents: mail, container, python)${N}"
  fi
elif [ -f "$DEST/scripts/setup/setup-devtools.sh" ]; then
  ln_ "  ${D}Optional devtools skipped (non-interactive). Later: bash $DEST/scripts/setup/setup-devtools.sh${N}"
fi

# Hand the user a FRESH login shell: this run added PATH lines to the shell rc
# (nvm, bun, brew, ~/.local/bin) that the current shell predates. A login shell
# picks them all up, so `pi` works immediately — no "open a new terminal" dance.
if has_tty && [ -t 1 ]; then
  ln_ ""
  ln_ "  ${G}Dropping you into a fresh shell${N} ${D}(all tools on PATH) — next: ${N}${C}pi${N}${D} → ${N}${C}/login${N}${D} (first time) → ${N}${C}/onboard${N}"
  exec "${SHELL:-/bin/zsh}" -l </dev/tty
fi
