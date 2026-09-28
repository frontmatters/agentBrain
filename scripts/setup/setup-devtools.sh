#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-devtools.sh — intent-gated optional devtools via the capability pattern
# (scripts/lib/platform.sh + scripts/lib/capability-install.sh). Standalone re-runnable;
# the installer may call it as an optional step. Read-only without a TTY choice:
# AGENTBRAIN_ASSUME_NO=1 declines everything (CI).
#
# Usage:
#   scripts/setup/setup-devtools.sh                 # interactive intent menu
#   scripts/setup/setup-devtools.sh mail            # install the tools for one intent
#   scripts/setup/setup-devtools.sh mail container  # several intents at once
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/lib/platform.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/lib/capability-install.sh"

# intent -> capability tokens (space-separated). New intents append here and
# add their capability arms in scripts/lib/capability-install.sh; nothing else changes.
intent_capabilities() {
	case "$1" in
		mail)      echo "mailpit" ;;
		container) echo "colima ttyd" ;;
		python)    echo "uv" ;;
		local-ai)  echo "ollama" ;;
		*)         echo "" ;;
	esac
}

INTENT_LIST="mail container python local-ai"

PROMPT_HELPER="$ROOT_DIR/scripts/installer/prompt-helper.sh"

if [ $# -gt 0 ]; then
	REQUESTED="$*"
else
	# Interactive: house checkbox menu (ab_prompt_multi, portable via /dev/tty).
	# Non-TTY: the menu fails closed to "nothing selected" with a hint.
	opts=()
	intents=()
	for intent in $INTENT_LIST; do
		caps="$(intent_capabilities "$intent")"
		[ -n "$caps" ] || continue
		opts+=("$intent -> $caps")
		intents+=("$intent")
	done
	[ ${#opts[@]} -gt 0 ] || { echo "no intents available"; exit 0; }
	# shellcheck source=scripts/installer/prompt-helper.sh
	. "$PROMPT_HELPER"
	REQUESTED=""
	if ab_prompt_multi --required "Optional devtools — toggle what this machine is for:" "${opts[@]}"; then
		i=0
		for intent in "${intents[@]}"; do
			case " $REPLY " in *" $i "*) REQUESTED="$REQUESTED $intent" ;; esac
			i=$((i + 1))
		done
		REQUESTED="${REQUESTED# }"
	fi
	[ -n "$REQUESTED" ] || { echo "nothing selected — run scripts/setup/setup-devtools.sh <intent> later (intents: ${intents[*]})"; exit 0; }
fi

installed_any=0
for intent in $REQUESTED; do
	caps="$(intent_capabilities "$intent")"
	if [ -z "$caps" ]; then
		echo "unknown intent: $intent (known: $INTENT_LIST)" >&2
		continue
	fi
	for cap in $caps; do
		if platform_has "$cap"; then
			echo "✓ $cap already present"
			continue
		fi
		offer_install "$cap" && installed_any=$((installed_any + 1))
	done
done

echo "done. installed/updated: $installed_any"
