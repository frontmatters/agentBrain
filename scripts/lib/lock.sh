#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lock.sh — serialize runs that share mutable state.
#
# Four doctor tests create fixtures with fixed names inside the real vault
# (local/spaces/__astest__ and friends), because note ids are derived from the
# real path and cannot be faked in a temp dir. Two doctor runs at once, say a
# manual one and the pre-push hook's, therefore trip over each other's
# fixtures and one fails for no reason in the code.
#
# Portable mkdir lock: no flock on macOS. Bounded wait; a lock left behind by
# a crashed run (older than the stale limit) is stolen rather than honoured,
# so nothing can wedge permanently.
#
# Usage:  source "$ROOT/scripts/lib/lock.sh"
#         acquire_lock doctor 180      # name, seconds to wait (default 180)
#         # released on EXIT automatically
acquire_lock() {
	local name="$1" wait="${2:-180}" stale="${3:-300}"
	local lock="${TMPDIR:-/tmp}/agentbrain-${name}.lock" i mt now
	# Reentrant down the process tree. Doctor runs tests, some tests run doctor
	# (or a hook that does); a child waiting on its own ancestor's lock would
	# sit out the full timeout at every nesting level. The holder exports a
	# marker; anything it spawns sees it and proceeds under the same lock.
	local held_var="AGENTBRAIN_LOCK_${name//[^A-Za-z0-9]/_}"
	[ -n "${!held_var:-}" ] && return 0
	for ((i = 0; i < wait; i++)); do
		if mkdir "$lock" 2>/dev/null; then
			export "$held_var=$$"
			# shellcheck disable=SC2064  # expand now: the path is fixed at acquire time
			trap "rmdir '$lock' 2>/dev/null || true" EXIT
			return 0
		fi
		mt="$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)"
		now="$(date +%s)"
		if [ "$mt" -gt 0 ] && [ $((now - mt)) -gt "$stale" ]; then
			rmdir "$lock" 2>/dev/null || true
			continue
		fi
		[ "$i" -eq 0 ] && echo "lock '$name' held by another run; waiting (up to ${wait}s)" >&2
		sleep 1
	done
	echo "lock '$name' still held after ${wait}s; proceeding without it" >&2
	return 1
}
