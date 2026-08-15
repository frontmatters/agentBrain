#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# _toolpaths.sh — load user-scoped tool locations so detection is HONEST.
# Tools installed earlier in the same run (or via an rc edit this process never
# sourced) live here; every script that probes tools sources this first, so we
# never claim "not installed" for something that is. Safe under set -u/-e.
# shellcheck disable=SC2148  # sourced library

if ! command -v brew >/dev/null 2>&1; then
	if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
	elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
fi
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ] && ! command -v nvm >/dev/null 2>&1; then
	set +u
	# shellcheck disable=SC1091
	. "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
	set -u 2>/dev/null || true
fi
case ":$PATH:" in *":$HOME/.bun/bin:"*) ;; *) [ -d "$HOME/.bun/bin" ] && PATH="$HOME/.bun/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH
