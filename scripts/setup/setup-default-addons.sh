#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-default-addons.sh — switch on the add-ons a fresh install is meant to
# have, and let the user untick them.
#
# Until this existed, a fresh install enabled nothing at all. The payload was
# there and every add-on was off, so the layer was only reachable by someone who
# already knew `/addons` existed. "Ships" and "is on" were the same decision
# made once, in the wrong direction.
#
# An add-on qualifies by carrying `default_enabled: true` in its manifest.
# check-addons refuses that field on anything that fetches software, sends
# content out, needs a runtime, or is not in the slim core, so everything
# offered here is local, present, and free of side effects.
#
# Interactive: pre-ticked, so unticking is the action. Non-interactive: the
# default applies, because that is what a default means when nobody is there to
# change it, and the guard above is what makes that safe.
set -uo pipefail

# WARNING for anyone testing this: ADDONS_STATE does not isolate you. Enabling
# an add-on syncs agent skill links, and that sync PRUNES links whose add-on is
# absent from the state it was handed. Point ADDONS_STATE at a fixture and the
# prune runs against the real ~/.claude, ~/.copilot and ~/.pi skill dirs, which
# is how this script's own first test emptied them. Test in a throwaway HOME.
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1
STATE="${ADDONS_STATE:-vault/addons}"

candidates=()
for m in system/addons/*/manifest.md; do
	[ -f "$m" ] || continue
	grep -qE '^default_enabled:[[:space:]]*(true|yes)[[:space:]]*$' "$m" || continue
	id="$(basename "$(dirname "$m")")"
	[ -f "$STATE/$id/enabled" ] && continue    # already on; nothing to ask
	candidates+=("$id")
done

[ "${#candidates[@]}" -gt 0 ] || { echo "default add-ons: already enabled"; exit 0; }

# The layer introduces itself here or nowhere. Before this line a new user met
# the word "addon" twice, both times inside a sentence about something else
# ("/onboard personalizes preferences, addons and locale"). Naming the count is
# what turns a word into a thing worth looking at.
announce_rest() {
	local total on rest
	total=0
	for _d in "$ROOT_DIR"/system/addons/*/; do
		[ -d "$_d" ] || continue
		[ "$(basename "$_d")" = "_template" ] && continue
		total=$((total + 1))
	done
	on="$(ls "$STATE" 2>/dev/null | wc -l | tr -d ' ')"
	rest=$((total - on))
	[ "$rest" -gt 0 ] && printf '  %d more available:  brain addons\n' "$rest"
	return 0
}

enable() {
	local failed=0 id
	for id in "$@"; do
		# install, not enable. The documented lifecycle is privacy gate, install
		# step, enable, health check, and `enable` is only the third of those: it
		# flips the marker and syncs skills. Enabling shorthand without its
		# install step left the glossary unwritten, and the check that only runs
		# for an ENABLED addon then reported drift on a fresh machine.
		# ADDONS_ASSUME_YES carries the consent that already happened. The privacy
		# gate refuses to enable without a terminal, which is right in general and
		# wrong here: the user either ticked this list or is running headless,
		# where the default applies by definition. It is only safe because
		# check-addons refuses default_enabled on anything that fetches software,
		# sends content out, or needs a runtime, so every add-on reaching this
		# line is local and inert.
		if ADDONS_ASSUME_YES=1 bash scripts/addons.sh install "$id" >/dev/null 2>&1; then
			echo "  enabled $id"
		else
			echo "  could not enable $id (try: brain addons enable $id)" >&2
			failed=1
		fi
	done
	return "$failed"
}

# A tty may exist on /dev/tty even when stdin is a pipe (curl | bash).
have_tty() { [ -t 0 ] || { [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }; }

if ! have_tty || [ "${AGENTBRAIN_ASSUME_YES:-0}" = "1" ]; then
	echo "Enabling the default add-ons (${#candidates[@]}): turn any off later with 'brain addons disable <id>'."
	enable "${candidates[@]}"; rc=$?
	announce_rest
	exit "$rc"
fi

# shellcheck source=../installer/prompt-helper.sh
. "$ROOT_DIR/scripts/installer/prompt-helper.sh" 2>/dev/null || {
	echo "Enabling the default add-ons (${#candidates[@]})."
	enable "${candidates[@]}"; exit $?
}

labels=(); preset=""; i=1
for id in "${candidates[@]}"; do
	name="$(sed -n 's/^name:[[:space:]]*//p' "system/addons/$id/manifest.md" | head -1)"
	labels+=("$id — ${name:-$id}")
	preset="$preset $i"; i=$((i + 1))
done

echo ""
echo "Default add-ons. All ticked; untick anything you would rather not have."
if ! ab_prompt_multi --default "${preset# }" "Enable these add-ons?" "${labels[@]}"; then
	echo "  Skipped. Later: brain addons enable <id>"
	exit 0
fi

chosen=()
for idx in $REPLY; do chosen+=("${candidates[$idx]}"); done
[ "${#chosen[@]}" -gt 0 ] || { echo "  Nothing selected. Later: brain addons enable <id>"; exit 0; }
enable "${chosen[@]}"; rc=$?
announce_rest
exit "$rc"
