#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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
		# "installed?" only — this gates install-offers (a present binary must not be
		# re-offered). Runtime health (ollama daemon up, a model pulled) is a separate,
		# per-capability concern the add-on's own preflight owns (e.g. graphify's
		# install.sh checks the daemon); probing it here would make offer_install
		# wrongly offer to install an already-present ollama whose daemon is merely idle.
		ollama)      command -v ollama >/dev/null 2>&1 ;;
		uv)          command -v uv >/dev/null 2>&1 ;;
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
	echo "keychain secret-tool browser node gpu display launchd systemd clipboard screenshot ollama uv devbox obsidian open-webui"
}
