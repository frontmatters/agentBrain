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
# shellcheck source=scripts/lib/platform.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform.sh"

acquire_lock() {
	local name="$1" wait="${2:-180}" stale="${3:-300}"
	local lock="${TMPDIR:-/tmp}/agentbrain-${name}.lock" i mt now holder
	# Reentrant down the process tree. Doctor runs tests, some tests run doctor
	# (or a hook that does); a child waiting on its own ancestor's lock would
	# sit out the full timeout at every nesting level. The holder exports a
	# marker; anything it spawns sees it and proceeds under the same lock.
	local held_var="AGENTBRAIN_LOCK_${name//[^A-Za-z0-9]/_}"
	[ -n "${!held_var:-}" ] && return 0
	for ((i = 0; i < wait; i++)); do
		if mkdir "$lock" 2>/dev/null; then
			# Who holds it. Without this a waiter cannot tell a running holder
			# from a crashed one, and cannot say whose run it is waiting for.
			printf '%s\n' "$$" > "$lock/pid" 2>/dev/null || true
			export "$held_var=$$"
			# shellcheck disable=SC2064  # expand now: the path is fixed at acquire time
			trap "rm -rf '$lock' 2>/dev/null || true" EXIT
			return 0
		fi
		# Liveness, not age. The rule used to be "older than $stale means
		# crashed", but mkdir stamps the mtime once and never again, so any run
		# outlasting that limit lost its lock to whoever was waiting. The full
		# doctor takes over ten minutes against a 300s limit: it was handing its
		# lock away halfway through, and then two ran at once over the same
		# fixtures, which is the exact collision this file exists to prevent.
		# A holder that is alive keeps it however long it needs; a holder that
		# died releases it on the next pass.
		holder="$(cat "$lock/pid" 2>/dev/null || true)"
		if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
			rm -rf "$lock" 2>/dev/null || true
			continue
		fi
		if [ -z "$holder" ]; then
			# No pid file: a lock from before this rule, or a mkdir that died
			# between creating the directory and writing into it. Fall back to
			# age so nothing can wedge permanently.
			# The dialect question lives in platform.sh, capability-probed once. The
			# reasoning that used to sit inline here, about GNU stat -f printing to
			# stdout and about uname sending busybox down the wrong branch, moved there
			# with it so the next caller inherits the answer instead of the trap.
			mt="$(platform_stat_mtime "$lock" 2>/dev/null || echo 0)"
			now="$(date +%s)"
			if [ "$mt" -gt 0 ] && [ $((now - mt)) -gt "$stale" ]; then
				rm -rf "$lock" 2>/dev/null || true
				continue
			fi
		fi
		[ "$i" -eq 0 ] && echo "lock '$name' held by pid ${holder:-unknown}; waiting (up to ${wait}s)" >&2
		sleep 1
	done
	# States the fact and nothing else. This used to read "proceeding without
	# it", which is a decision the caller makes: doctor refuses to run, other
	# callers may carry on. Two contracts on one return code meant the library
	# thought it was warning while the caller read it as an error.
	echo "lock '$name' still held by pid ${holder:-unknown} after ${wait}s" >&2
	return 1
}
