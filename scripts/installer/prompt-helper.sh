#!/usr/bin/env bash
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
