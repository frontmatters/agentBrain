#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# capability-install.sh — provision half of the capability pattern. Sourceable,
# no side-effects on source. Pairs with platform.sh (the probe half).
# Depends on platform_os/platform_has being sourced first.
#
# This file is intentionally ASCII-only: non-ASCII bytes next to variable
# expansions have caused unbound-variable crashes under `set -u`.

# Homebrew lives in /opt/homebrew (Apple Silicon) or /usr/local (Intel), but a
# narrow PATH (ssh wrappers, non-login shells) hides it -- offers would then
# wrongly report "no install recipe". Probe the standard locations once.
if ! command -v brew >/dev/null 2>&1; then
	for _ab_brew in /opt/homebrew/bin /usr/local/bin; do
		if [ -x "$_ab_brew/brew" ]; then
			PATH="$_ab_brew:$PATH"
			export PATH
			break
		fi
	done
	unset _ab_brew
fi

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
		jq)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install jq"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y jq"
			fi ;;
		mailpit)
			if [ "$os" = darwin ]; then
				command -v brew >/dev/null 2>&1 && echo "brew install mailpit"
			elif command -v docker >/dev/null 2>&1; then
				echo "docker run -d --name mailpit -p 8025:8025 -p 1025:1025 axllent/mailpit"
			else
				local mparch; mparch="$(platform_arch)"; [ "$mparch" = x86_64 ] && mparch=amd64
				echo "curl -fsSL https://github.com/axllent/mailpit/releases/latest/download/mailpit-linux-${mparch}.tar.gz | sudo tar -xz -C /usr/local/bin mailpit"
			fi ;;
		ripgrep)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install ripgrep"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y ripgrep"
			fi ;;
		fd)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install fd"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y fd-find"
			fi ;;
		yq)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install yq"
			else
				local yarch; yarch="$(platform_arch)"; [ "$yarch" = arm64 ] && yarch=arm64
				echo "curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yarch} | sudo tee /usr/local/bin/yq >/dev/null && sudo chmod +x /usr/local/bin/yq"
			fi ;;
		shellcheck)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install shellcheck"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y shellcheck"
			fi ;;
		wget)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install wget"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y wget"
			fi ;;
		fzf)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install fzf"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y fzf"
			fi ;;
		gh)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install gh"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y gh"
			fi ;;
		ffmpeg)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install ffmpeg"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y ffmpeg"
			fi ;;
		imagemagick)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install imagemagick"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y imagemagick"
			fi ;;
		git-lfs)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install git-lfs"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y git-lfs"
			fi ;;
		yt-dlp)
			# apt's yt-dlp is chronically stale: on linux use the pinned binary.
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install yt-dlp"
			else
				echo "sudo curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && sudo chmod a+rx /usr/local/bin/yt-dlp"
			fi ;;
		colima)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install colima docker"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y docker.io"
			fi ;;
		ttyd)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew install ttyd"
			elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y ttyd"
			fi ;;
	esac
}

# OS-aware reinstall command (the install recipe, re-run). Empty when unknown.
capability_reinstall_cmd() {
	local c; c="$(capability_install_cmd "$1")"
	case "$c" in
		brew\ install\ --cask\ *) echo "${c/install\ --cask/reinstall --cask}" ;;
		brew\ install*)           echo "${c/install/reinstall}" ;;
		*) echo "$c" ;;
	esac
}

# Service-start command for a capability (empty = nothing to start).
# A binary alone is a half install: Ollama needs its daemon serving.
capability_start_cmd() {
	local os; os="$(platform_os)"
	case "$1" in
		ollama)
			if [ "$os" = darwin ] && command -v brew >/dev/null 2>&1; then echo "brew services start ollama"; fi ;;
		colima)
			if [ "$os" = darwin ]; then echo "colima start"; else echo "sudo systemctl start docker"; fi ;;
	esac
}

# Health probe: is the capability's runtime actually serving?
capability_health_cmd() {
	case "$1" in
		ollama) echo "curl -fsS -m 2 http://localhost:11434/" ;;
		mailpit) echo "curl -fsS -m 2 http://localhost:8025/api/v1/messages" ;;
		colima) echo "docker info" ;;
		*) : ;;
	esac
}

# After install/update/reinstall: make sure the daemon is actually up.
ensure_running() {
	local cap="$1"
	local hc; hc="$(capability_health_cmd "$cap")"
	[ -n "$hc" ] || return 0
	if eval "$hc" >/dev/null 2>&1; then
		echo "  $cap daemon: running"
		return 0
	fi
	local sc; sc="$(capability_start_cmd "$cap")"
	if [ -z "$sc" ]; then return 0; fi
	echo "  Starting $cap daemon ($sc)"
	eval "$sc" </dev/null >/dev/null 2>&1 || true
	local _i
	for _i in 1 2 3 4 5; do
		if eval "$hc" >/dev/null 2>&1; then echo "  $cap daemon: running"; return 0; fi
		sleep 1
	done
	echo "  $cap daemon did not come up. Start it later: $sc" >&2
	return 1
}

# True when a recipe is safe to auto-run on opt-in: a user-level package-manager
# install. Pipe-to-shell, services, and privilege-escalating (sudo) recipes are
# show-only (never auto-run) -- the sudo arm must precede the allow arm so e.g.
# "sudo snap install ..." is shown, not silently password-prompted mid-flow.
_recipe_auto_runnable() {
	case "$1" in
		*"| sh"*|*"| bash"*|*"docker "*|*"sudo "*) return 1 ;;
		brew\ *|*"flatpak "*|*"snap "*) return 0 ;;
		*) return 1 ;;
	esac
}

# offer_install <capability>. One visible question, never a silent skip:
#   present -> keep / update / reinstall / skip (skip is the default)
#   absent  -> install / skip (No is the default)
# Exit: 0 available/kept/running, 1 declined/skipped, 2 recipe ran but still absent.
# Env AGENTBRAIN_ASSUME_NO=1 forces the non-interactive decline (tests/CI).
offer_install() {
	local cap="$1" cmd
	# Present? Then offer maintenance -- same shape as the developer-tools
	# questions (bun/uv): keep / update / reinstall / skip (skip default).
	if platform_has "$cap"; then
		if [ "${AGENTBRAIN_ASSUME_NO:-0}" = 1 ] || [ ! -t 0 ]; then
			echo "  $cap present -- kept as is."
			return 0
		fi
		# shellcheck source=../installer/prompt-helper.sh
		. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../installer/prompt-helper.sh"
		# update comes from the INSTALL recipe (brew install -> brew upgrade);
		# deriving it from the reinstall recipe would yield "brew reupgrade".
		local icmd; icmd="$(capability_install_cmd "$cap")"
		local up=""
		case "$icmd" in brew\ *) up="${icmd/install/upgrade}" ;; esac
		cmd="$(capability_reinstall_cmd "$cap")"
		local re="$cmd"
		# Detected -> the honest default is to change nothing (skip).
		if ! ab_prompt_select --default 4 "$cap: what should we do?" \
			"keep -- present and fine" "update -- fetch latest" \
			"reinstall -- run the installer again" "skip -- continue without changes"; then
			return 0
		fi
		# REPLY is the zero-based row index: 0=keep, 1=update, 2=reinstall, 3=skip.
		case "$REPLY" in
			0) return 0 ;;
			1)
				if [ -n "$up" ]; then
					echo "  Updating $cap (brew upgrade)"
					eval "$up" </dev/null || true
					platform_has "$cap" && { ensure_running "$cap"; return 0; }
					echo "  $cap update ran but is still absent." >&2
					return 2
				fi
				echo "  No update recipe for $cap -- kept as is."
				return 0 ;;
			2)
				echo "  Reinstalling $cap (brew reinstall)"
				eval "$re" </dev/null || true
				platform_has "$cap" && { ensure_running "$cap"; return 0; }
				echo "  $cap reinstall ran but is still absent." >&2
				return 2 ;;
			*) echo "  Skipped. $cap stays as is."; return 1 ;;
		esac
	fi
	cmd="$(capability_install_cmd "$cap")"
	if [ -z "$cmd" ]; then
		echo "  $cap not found -- no install recipe for this OS. See its docs." >&2
		return 1
	fi
	if [ "${AGENTBRAIN_ASSUME_NO:-0}" = 1 ] || [ ! -t 0 ]; then
		echo "  $cap not found. Later: $cmd" >&2
		return 1
	fi
	if _recipe_auto_runnable "$cmd"; then
		# shellcheck source=../installer/prompt-helper.sh
		. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../installer/prompt-helper.sh"
		# stdin from /dev/null: the recipe (e.g. brew) must run non-interactively --
		# its own "proceed? [y/n]" prompts would otherwise collide with our terminal.
		if ab_prompt_confirm --default no "Install $cap now?"; then
			eval "$cmd" </dev/null || true
			if platform_has "$cap"; then
				ensure_running "$cap"
				return 0
			fi
			echo "  $cap install ran but is still absent." >&2
			return 2
		fi
		echo "  Skipped. Later: $cmd" >&2
		return 1
	else
		echo "  $cap not found. Run this yourself (not auto-run for safety):" >&2
		echo "    $cmd" >&2
		return 1
	fi
}
