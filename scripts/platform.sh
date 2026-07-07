#!/usr/bin/env bash
# platform.sh — single source of truth voor platform-detectie. Sourcebaar.
# Geen side-effects bij source; alleen functie-definities.

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

# Canonieke id: macos-arm64 | linux-aarch64 | linux-x86_64
platform_id() {
	local os arch
	os="$(platform_os)"; arch="$(platform_arch)"
	[ "$os" = darwin ] && os=macos
	[ "$os" = linux ] && [ "$arch" = arm64 ] && arch=aarch64
	echo "${os}-${arch}"
}

# Functionele capability-probe: exit 0 = aanwezig, 1 = afwezig.
# "Functioneel" = de probe moet daadwerkelijk slagen, niet enkel op PATH staan.
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
		screenshot)  command -v snapcoder >/dev/null 2>&1 || command -v grim >/dev/null 2>&1 || command -v scrot >/dev/null 2>&1 ;;
		*)           return 1 ;;
	esac
}
