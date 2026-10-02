#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-optional-addons.sh — offer the registry add-ons a fresh install does not
# carry, none ticked, and install the ones picked.
#
# An add-on brings its own prerequisites: installing one runs the privacy
# question and then offers every runtime its manifest declares
# (runtime_requires), so yt-dlp arrives with youtube-digest and ollama with the
# add-ons that need it, and nothing arrives for an add-on nobody picked. That is
# why the core install no longer asks about those tools itself.
#
# Unlike the default add-ons step this never answers for the user: these may
# send content out or install software, so each question stays with the person
# at the terminal. Without a terminal the step only says where to find them.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

have_tty() { [ -t 0 ] || { [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }; }
later() { echo "  Later: brain addons (browse, then brain addons install <id>)"; }

if ! have_tty || [ "${AGENTBRAIN_ASSUME_YES:-0}" = "1" ]; then
	echo "Optional add-ons are not installed without you choosing them."
	later; exit 0
fi

offer="$(bash scripts/addons.sh offerable 2>/dev/null || true)"
if [ -z "$offer" ]; then
	echo "No optional add-ons to offer (registry unreachable, or all present)."
	later; exit 0
fi

# shellcheck source=../installer/prompt-helper.sh
. "$ROOT_DIR/scripts/installer/prompt-helper.sh" 2>/dev/null || { later; exit 0; }

privacy_label() {
	case "$1" in
		sends-all)  echo "sends data to an outside service" ;;
		sends-docs) echo "sends selected notes to a model you choose" ;;
		local-only) echo "stays on this machine, never syncs" ;;
		*)          echo "stays on this machine" ;;
	esac
}

ids=(); labels=()
while IFS=$'\t' read -r id name privacy runtime; do
	[ -n "$id" ] || continue
	# offerable writes "-" for an empty field so the columns never shift.
	[ "$name" = "-" ] && name=""; [ "$privacy" = "-" ] && privacy=""; [ "$runtime" = "-" ] && runtime=""
	needs="${runtime:+; installs ${runtime// /, } when enabled}"
	ids+=("$id")
	labels+=("${name:-$id} ($(privacy_label "$privacy")${needs})")
done <<<"$offer"

echo ""
echo "Optional add-ons. None ticked; each one you pick asks its own questions."
if ! ab_prompt_multi --default "" "Install any of these?" "${labels[@]}"; then
	later; exit 0
fi
chosen=()
for idx in $REPLY; do chosen+=("${ids[$idx]}"); done
[ "${#chosen[@]}" -gt 0 ] || { echo "  Nothing picked."; later; exit 0; }

failed=0
for id in "${chosen[@]}"; do
	echo ""
	if bash scripts/addons.sh install "$id" </dev/tty; then
		echo "  installed $id"
	else
		echo "  $id not installed (try later: brain addons install $id)" >&2
		failed=1
	fi
done
exit "$failed"
