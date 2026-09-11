#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib/editors.sh -- find the VS Code family editors on this machine. Sourceable,
# no side effects on source.
#
# Why this is not platform_has: that helper answers "is the binary on PATH",
# which is the wrong question for a GUI editor. On macOS, VS Code ships its
# `code` CLI INSIDE the app bundle and only puts it on PATH once the user runs
# "Shell Command: Install 'code' command in PATH" from the palette. Checking
# PATH alone reported "VS Code not installed" on a machine that had it, and
# sent the user off to download what they already had.
#
# It also answers a second question PATH cannot: WHICH editor. Cursor ships a
# `code` binary of its own, so `command -v code` can succeed while pointing at
# a different editor than the row said. A machine can carry several at once.
#
# API:
#   editor_flavors            one line per detected editor: id|label|cli|marketplace
#   editor_cli <id>           absolute path to that editor's CLI, empty if absent
#   editor_label <id>         human label
#   editor_marketplace <id>   "microsoft" or "openvsx"
#
# The marketplace field matters for extension rows: VSCodium pulls from Open VSX,
# which does not carry every extension the Microsoft marketplace does.

# id:label:cli-name:app-bundle:marketplace
_EDITOR_TABLE='vscode:Visual Studio Code:code:Visual Studio Code:microsoft
vscode-insiders:VS Code Insiders:code-insiders:Visual Studio Code - Insiders:microsoft
vscodium:VSCodium:codium:VSCodium:openvsx
cursor:Cursor:cursor:Cursor:microsoft
windsurf:Windsurf:windsurf:Windsurf:microsoft'

# Editors outside the VS Code family. They take no extensions through this
# menu, so they carry no marketplace: they exist here only so that "which
# editor do you use" has one implementation instead of two. The onboarding
# wizard used to repeat the PATH and app-bundle probes in its own Python.
# id:label:cli-name:app-bundle
_EDITOR_OTHER_TABLE='zed:Zed:zed:Zed
neovim:Neovim / Vim:nvim:'

# Preferred editor for the "which editor do you use" question, as a label.
# Order is deliberate and matches what the wizard did before this was shared:
# Cursor wins over VS Code, because someone running both usually means Cursor.
# PATH is checked for every candidate before any app bundle, so a linked CLI
# beats an installed-but-unlinked editor.
editor_detect_preferred() {
	local id label cli app _mk
	for id in cursor vscode zed neovim vscodium vscode-insiders windsurf; do
		if label="$(editor_label "$id" 2>/dev/null)"; then
			cli="$(_editor_cli_name "$id")"
			[ -n "$cli" ] && command -v "$cli" >/dev/null 2>&1 && { printf '%s\n' "$label"; return 0; }
		fi
	done
	# No CLI anywhere: fall back to an installed app bundle, same order.
	for id in cursor vscode zed vscodium vscode-insiders windsurf; do
		if editor_cli "$id" >/dev/null 2>&1; then
			editor_label "$id"
			return 0
		fi
	done
	return 1
}

# CLI NAME (not path) for an id, across both tables.
_editor_cli_name() {
	local want="$1" id _l cli _a _m
	while IFS=: read -r id _l cli _a _m; do
		[ "$id" = "$want" ] && { printf '%s\n' "$cli"; return 0; }
	done <<EOF
$_EDITOR_TABLE
$_EDITOR_OTHER_TABLE
EOF
	return 1
}

# Resolve one editor's CLI: PATH first, then inside the macOS app bundle.
editor_cli() {
	local want="$1" id label cli app _mk
	while IFS=: read -r id label cli app _mk; do
		[ "$id" = "$want" ] || continue
		if command -v "$cli" >/dev/null 2>&1; then
			command -v "$cli"
			return 0
		fi
		# macOS: the CLI lives in the bundle whether or not it was linked.
		local bundled="/Applications/$app.app/Contents/Resources/app/bin/$cli"
		if [ -x "$bundled" ]; then
			printf '%s\n' "$bundled"
			return 0
		fi
		# Editors outside the VS Code family put their CLI elsewhere in the
		# bundle (Zed: Contents/MacOS/cli). Treat the app itself as proof the
		# editor is installed; nothing here installs extensions into them.
		if [ -n "$app" ] && [ -d "/Applications/$app.app" ]; then
			printf '%s\n' "/Applications/$app.app"
			return 0
		fi
	done <<EOF
$_EDITOR_TABLE
$_EDITOR_OTHER_TABLE
EOF
	return 1
}

editor_label() {
	local want="$1" id label _c _a _m
	while IFS=: read -r id label _c _a _m; do
		[ "$id" = "$want" ] && { printf '%s\n' "$label"; return 0; }
	done <<EOF
$_EDITOR_TABLE
$_EDITOR_OTHER_TABLE
EOF
	return 1
}

editor_marketplace() {
	local want="$1" id _l _c _a mk
	while IFS=: read -r id _l _c _a mk; do
		[ "$id" = "$want" ] && { printf '%s\n' "$mk"; return 0; }
	done <<EOF
$_EDITOR_TABLE
EOF
	return 1
}

# One line per editor present: id|label|cli|marketplace
editor_flavors() {
	local id label _c _a mk cli
	while IFS=: read -r id label _c _a mk; do
		cli="$(editor_cli "$id")" || continue
		printf '%s|%s|%s|%s\n' "$id" "$label" "$cli" "$mk"
	done <<EOF
$_EDITOR_TABLE
EOF
}
