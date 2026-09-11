#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-editors.sh — editor detection must see an app bundle, not just PATH.
#
# The regression: the VS Code extension rows guarded on `command -v code`. On
# macOS that binary reaches PATH only after the user runs "Shell Command:
# Install 'code' command in PATH" from the palette, so an installed VS Code
# was reported as absent and the user was told to install what they already
# had. A second machine carried VS Code, VSCodium and Cursor at once, and
# `command -v code` could not tell which one it had found: Cursor ships a
# `code` binary of its own.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-editors.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=../lib/editors.sh
. "$ROOT_DIR/lib/editors.sh"

# --- 1. a CLI on PATH is found ----------------------------------------------
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho 1.0.0\n' > "$TMP/bin/codium"
chmod +x "$TMP/bin/codium"
if PATH="$TMP/bin:$PATH" editor_cli vscodium | grep -q "$TMP/bin/codium"; then
	ok "a CLI on PATH is found"
else
	bad "did not find a CLI that is on PATH"
fi

# --- 2. an absent editor is absent ------------------------------------------
# windsurf is the control: nothing on PATH, no bundle in this fixture.
if PATH="$TMP/bin" editor_cli windsurf >/dev/null 2>&1; then
	bad "reported an editor that is not installed"
else
	ok "an absent editor stays absent"
fi

# --- 3. each id carries a label and a marketplace ----------------------------
# The marketplace drives the Copilot decision, so a blank one is a real defect.
for id in vscode vscodium cursor windsurf vscode-insiders; do
	lbl="$(editor_label "$id")"; mk="$(editor_marketplace "$id")"
	[ -n "$lbl" ] || bad "no label for $id"
	case "$mk" in microsoft|openvsx) ;; *) bad "bad marketplace for $id: '$mk'" ;; esac
done
ok "every id has a label and a known marketplace"

# --- 4. VSCodium is on Open VSX, the rest on the Microsoft marketplace -------
# Verified against both registries on 2026-09-11: GitHub.copilot returns 404 on
# open-vsx.org and 200 on the Microsoft marketplace. An extension row must be
# able to see that difference before it tries to install.
[ "$(editor_marketplace vscodium)" = openvsx ] \
	&& ok "VSCodium resolves to Open VSX" \
	|| bad "VSCodium must resolve to Open VSX"
[ "$(editor_marketplace vscode)" = microsoft ] \
	&& ok "VS Code resolves to the Microsoft marketplace" \
	|| bad "VS Code must resolve to the Microsoft marketplace"

# --- 5. the output shape is parseable ---------------------------------------
# install-agent-clis.sh splits these on '|' into id, label, cli, marketplace.
bad_line=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	[ "$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')" = "3" ] || bad_line=1
done < <(editor_flavors)
[ "$bad_line" -eq 0 ] && ok "every flavour line has four fields" || bad "malformed flavour line"

# --- 6. platform_has consults the bundle, not only PATH ----------------------
# shellcheck source=../lib/platform.sh
. "$ROOT_DIR/lib/platform.sh"
if [ -d "/Applications/Visual Studio Code.app" ]; then
	if platform_has vscode; then
		ok "platform_has sees an app bundle without the CLI on PATH"
	else
		bad "platform_has missed an installed VS Code (bundle present)"
	fi
else
	printf '  skip: no VS Code app bundle on this machine\n'
fi

# --- 7. the preferred-editor detection the wizard relies on ------------------
# Regression: onboard-wizard.sh carried its own copy of these probes in Python.
# The copy checked PATH and /Applications separately and missed the macOS case
# where an editor ships its CLI inside the bundle unlinked, so a machine with
# VS Code installed detected no editor at all.
pref="$(editor_detect_preferred 2>/dev/null || true)"
if [ -n "$pref" ]; then
	ok "a preferred editor is detected ($pref)"
else
	printf '  skip: no editor installed on this machine\n'
fi

# Cursor outranks VS Code when both are present: running both usually means
# Cursor is the one in use. The wizard had this order before the move.
if editor_cli cursor >/dev/null 2>&1 && editor_cli vscode >/dev/null 2>&1; then
	[ "$pref" = "Cursor" ] \
		&& ok "Cursor outranks VS Code when both are installed" \
		|| bad "expected Cursor to win, got $pref"
fi

# --- 8. non-VS-Code editors are detectable but never extension targets -------
# Zed and Neovim answer "which editor do you use". They must not appear as a
# place to install a VS Code extension into.
if [ -d /Applications/Zed.app ] || command -v zed >/dev/null 2>&1; then
	editor_cli zed >/dev/null 2>&1 \
		&& ok "Zed is detected" \
		|| bad "Zed is installed but not detected"
	editor_flavors | grep -q "^zed|" \
		&& bad "Zed must not be offered as an extension target" \
		|| ok "Zed stays out of the extension flavours"
fi

printf 'editors: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
