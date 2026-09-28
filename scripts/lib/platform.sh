#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# platform.sh: single source of truth for platform detection. Sourceable.
# No side effects on source; function definitions only.

# Resolved while sourcing: inside a function BASH_SOURCE no longer points here,
# so a lazy `source` of a sibling lib would look in the caller's directory.
_PLATFORM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detection is only honest once the user-scoped tool locations are loaded. bun,
# node and uv live in nvm, ~/.bun and ~/.local/bin, which a restricted PATH does
# not carry, so platform_has said "not installed" for tools that were installed
# and offer_install then offered to install them again. _toolpaths.sh is
# idempotent and safe under set -u.
# shellcheck disable=SC1091
[ -f "$_PLATFORM_LIB_DIR/_toolpaths.sh" ] && . "$_PLATFORM_LIB_DIR/_toolpaths.sh"

platform_os() {
	case "$(uname -s)" in
		Darwin) echo darwin ;;
		Linux)  echo linux ;;
		*)      echo unknown ;;
	esac
}

platform_arch() {
	case "$(uname -m)" in
		arm64|aarch64) echo arm64 ;;
		x86_64|amd64)  echo x86_64 ;;
		*)             echo unknown ;;
	esac
}

# Portable filesystem metadata. Callers must not grow their own Darwin/GNU
# stat branches: this is the single platform seam for mode and mtime checks.
# Which stat(1) dialect is here? Probe the CAPABILITY, never the identity.
#
# BSD and GNU stat use -f for unrelated things, so `stat -f … || stat -c …` cannot
# work as a fallback: GNU stat -f fails, but prints its own output to stdout first,
# and command substitution keeps it. A caller asking for an mtime receives
# '  File: "/path"' instead of a number while 2>/dev/null silences only stderr.
# In lock.sh that meant every lock looked fresh and a stale lock was never stolen,
# which is the one thing that code promises to do.
#
# Asking `uname -s` instead sends busybox down the BSD branch, where -c is exactly
# what does work. So the question is "does -c work here", asked once.
_platform_stat_gnu() { stat -c %Y /dev/null >/dev/null 2>&1; }

platform_stat_mode() {
	if _platform_stat_gnu; then
		stat -c '%a' "$1"
	else
		stat -f '%Lp' "$1"
	fi
}

platform_stat_mtime() {
	if _platform_stat_gnu; then
		stat -c '%Y' "$1"
	else
		stat -f '%m' "$1"
	fi
}

# Flavor: native or WSL. WSL is linux with Windows interop; it is NOT a third
# OS but a flavor that overrides a few capability arms (browser via
# wslview, clipboard via clip.exe). Fastest reliable signals first.
platform_flavor() {
	if [ -n "${WSL_DISTRO_NAME:-}" ]; then echo wsl
	elif grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
	else echo native; fi
}

# WSL generation within the flavor: "2" | "1" | "" (unknown). Layered detection,
# deliberately NOT only on the kernel string: custom kernels (.wslconfig) lack
# "microsoft-standard-WSL2", so naive sniffers (nvm/pnpm) classify a WSL2 distro
# as WSL1 (a false positive).
#   1) binfmt interop: only WSL2 registers WSLInterop in binfmt_misc.
#   2) wslinfo --wsl-version (modern WSL app): "1"/"2" or a WSL1/WSL2 prefix.
#   3) the kernel string as a last resort.
platform_wsl_version() {
	platform_flavor | grep -q wsl || return 0
	if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then echo 2; return 0; fi
	local v
	if command -v wslinfo >/dev/null 2>&1; then
		v="$(wslinfo --wsl-version 2>/dev/null || true)"
		case "$v" in
			2*|WSL2*) echo 2; return 0 ;;
			1*|WSL1*) echo 1; return 0 ;;
		esac
	fi
	case "$(uname -r)" in
		*microsoft-standard*|*WSL2*) echo 2; return 0 ;;
		*-Microsoft*) echo 1; return 0 ;;
	esac
	echo ""
}

# Canonical id: macos-arm64 | linux-aarch64 | linux-x86_64 | wsl-x86_64 | wsl-aarch64
platform_id() {
	local os arch flavor
	os="$(platform_os)"; arch="$(platform_arch)"; flavor="$(platform_flavor)"
	[ "$os" = darwin ] && os=macos
	[ "$os" = linux ] && [ "$arch" = arm64 ] && arch=aarch64
	[ "$flavor" = wsl ] && [ "$os" = linux ] && os=wsl
	echo "${os}-${arch}"
}

# Functional capability probe: exit 0 = present, 1 = absent.
# "Functional" = the probe must actually succeed, not merely be on PATH.
platform_has() {
	case "$1" in
		keychain)    [ "$(platform_os)" = darwin ] && command -v security >/dev/null 2>&1 ;;
		secret-tool) command -v secret-tool >/dev/null 2>&1 ;;
		browser)     command -v chromium-browser >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || command -v playwright >/dev/null 2>&1 ;;
		node)        command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 ;;
		gpu)         command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 ;;
		display)     [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] ;;
		launchd)     [ "$(platform_os)" = darwin ] && command -v launchctl >/dev/null 2>&1 ;;
		systemd)     command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1 ;;
		clipboard)   command -v pbcopy >/dev/null 2>&1 || command -v xclip >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1 ;;
		screenshot)  { [ -n "${AGENTBRAIN_SCREENSHOT_CMD:-}" ] && command -v "$AGENTBRAIN_SCREENSHOT_CMD" >/dev/null 2>&1; } || command -v grim >/dev/null 2>&1 || command -v scrot >/dev/null 2>&1 ;;
		# "installed?" only — this gates install-offers (a present binary must not be
		# re-offered). Runtime health (ollama daemon up, a model pulled) is a separate,
		# per-capability concern the add-on's own preflight owns (e.g. graphify's
		# install.sh checks the daemon); probing it here would make offer_install
		# wrongly offer to install an already-present ollama whose daemon is merely idle.
		# Editors: PATH is not enough. On macOS the CLI ships inside the app
		# bundle and reaches PATH only after the user runs the palette command,
		# so a PATH-only probe reports "absent" for an installed editor and
		# offer_install would offer to install it again. lib/editors.sh knows
		# both locations; source it lazily so platform.sh stays dependency-free.
		vscode|vscodium|cursor|windsurf|vscode-insiders)
			# shellcheck source=./editors.sh
			. "$_PLATFORM_LIB_DIR/editors.sh"
			editor_cli "$1" >/dev/null 2>&1 ;;
		ollama)      command -v ollama >/dev/null 2>&1 ;;
		jq)          command -v jq >/dev/null 2>&1 ;;
		mailpit)     command -v mailpit >/dev/null 2>&1 ;;
		ripgrep)     command -v rg >/dev/null 2>&1 ;;
		fd)          command -v fdfind >/dev/null 2>&1 || command -v fd >/dev/null 2>&1 ;;
		yq)          command -v yq >/dev/null 2>&1 ;;
		shellcheck)  command -v shellcheck >/dev/null 2>&1 ;;
		wget)        command -v wget >/dev/null 2>&1 ;;
		fzf)         command -v fzf >/dev/null 2>&1 ;;
		gh)          command -v gh >/dev/null 2>&1 ;;
		ffmpeg)      command -v ffmpeg >/dev/null 2>&1 ;;
		imagemagick) command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 ;;
		git-lfs)     command -v git-lfs >/dev/null 2>&1 ;;
		colima)       command -v colima >/dev/null 2>&1 ;;
		ttyd)         command -v ttyd >/dev/null 2>&1 ;;
		docker)       command -v docker >/dev/null 2>&1 ;;
		uv)          command -v uv >/dev/null 2>&1 ;;
		bun)         command -v bun >/dev/null 2>&1 && bun --version >/dev/null 2>&1 ;;
		yt-dlp)      command -v yt-dlp >/dev/null 2>&1 ;;
		routa)       command -v routa >/dev/null 2>&1 ;;
		devbox)      command -v devbox >/dev/null 2>&1 ;;
		obsidian)    { [ "$(platform_os)" = darwin ] && [ -d "/Applications/Obsidian.app" ]; } || command -v obsidian >/dev/null 2>&1 ;;
		open-webui)  command -v curl >/dev/null 2>&1 && curl -fsS -m 2 http://localhost:8080/health >/dev/null 2>&1 ;;
		*)           return 1 ;;
	esac
}

# Enumerate the capability tokens platform_has knows. Kept adjacent to the case
# above so the two stay in sync (check-addons validates runtime_requires against
# this list). Space-separated.
platform_capabilities() {
	echo "keychain secret-tool browser node gpu display launchd systemd clipboard screenshot ollama uv bun yt-dlp routa devbox obsidian open-webui jq mailpit ripgrep fd yq shellcheck wget fzf gh ffmpeg imagemagick git-lfs colima ttyd docker"
}
