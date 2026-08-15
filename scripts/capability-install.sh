#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# capability-install.sh — provision half of the capability pattern. Sourceable,
# no side-effects on source. Pairs with platform.sh (the probe half).
# Depends on platform_os/platform_has being sourced first.

# OS-aware install command for a capability, or empty if none is known here.
# A "show-only" recipe (services, pipe-to-shell) is still returned as a string;
# offer_install decides whether it may auto-run (see run-safety below).
capability_install_cmd() {
	local os; os="$(platform_os)"
	case "$1" in
		obsidian)
			if [ "$os" = darwin ]; then command -v brew >/dev/null 2>&1 && echo "brew install --cask obsidian"
			elif command -v flatpak >/dev/null 2>&1; then echo "flatpak install -y flathub md.obsidian.Obsidian"
			elif command -v snap >/dev/null 2>&1; then echo "sudo snap install obsidian --classic"; fi ;;
		ollama)
			if [ "$os" = darwin ]; then command -v brew >/dev/null 2>&1 && echo "brew install ollama"
			else echo "curl -fsSL https://ollama.com/install.sh | sh"; fi ;;
		uv)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install uv"
			else echo "curl -LsSf https://astral.sh/uv/install.sh | sh"; fi ;;
		devbox)
			echo "curl -fsSL https://get.jetify.com/devbox | bash" ;;
		open-webui)
			echo "docker run -d -p 8080:8080 --name open-webui ghcr.io/open-webui/open-webui:main" ;;
	esac
}

# True when a recipe is safe to auto-run on opt-in: a user-level package-manager
# install. Pipe-to-shell, services, and privilege-escalating (sudo) recipes are
# show-only (never auto-run) — the sudo arm must precede the allow arm so e.g.
# `sudo snap install …` is shown, not silently password-prompted mid-flow.
_recipe_auto_runnable() {
	case "$1" in
		*"| sh"*|*"| bash"*|*"docker "*|*"sudo "*) return 1 ;;
		brew\ *|*"flatpak "*|*"snap "*) return 0 ;;
		*) return 1 ;;
	esac
}

# offer_install <capability>: probe; if present -> 0. If absent, prompt opt-in
# (N default) with the recipe + a "Later:" fallback. Auto-run only safe recipes on
# opt-in; show-only otherwise. Re-probe. Exit: 0 available, 1 declined/absent,
# 2 install ran but still absent.
# Env AGENTBRAIN_ASSUME_NO=1 forces the non-interactive decline (tests/CI).
offer_install() {
	local cap="$1" cmd
	if platform_has "$cap"; then return 0; fi
	cmd="$(capability_install_cmd "$cap")"
	if [ -z "$cmd" ]; then
		echo "  $cap not found — no install recipe for this OS. See its docs." >&2
		return 1
	fi
	if [ "${AGENTBRAIN_ASSUME_NO:-0}" = 1 ] || [ ! -t 0 ]; then
		echo "  $cap not found. Later: $cmd" >&2
		return 1
	fi
	if _recipe_auto_runnable "$cmd"; then
		printf '  Install %s now? [y/N] (later: %s) ' "$cap" "$cmd"
		read -r reply
		case "$reply" in
			[yY]*) eval "$cmd" || true
			       if platform_has "$cap"; then return 0; else echo "  $cap install ran but is still absent." >&2; return 2; fi ;;
			*) echo "  Skipped. Later: $cmd" >&2; return 1 ;;
		esac
	else
		echo "  $cap not found. Run this yourself (not auto-run for safety):" >&2
		echo "    $cmd" >&2
		return 1
	fi
}
