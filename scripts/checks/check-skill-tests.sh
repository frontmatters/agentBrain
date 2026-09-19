#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-skill-tests.sh — run every test a skill ships with.
#
# Skills carry their own test.sh. The doctor listed unit tests by hand, so a
# skill test was covered only if someone remembered to add a line. Nobody had:
# wash-vault/test.sh existed for weeks and ran nowhere. A test that nothing
# executes is not a safety net, it is a comment that looks like one.
#
# Discovering them removes the list, and with it the drift. A skill that adds a
# test.sh is covered by the next doctor run, with no edit here.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

ran=0; failed=0; names=""
while IFS= read -r t; do
	[ -f "$t" ] || continue
	skill="$(basename "$(dirname "$t")")"
	ran=$((ran + 1))
	# Run each test from its own directory. A skill test is written next to the
	# thing it tests and reads its siblings by name; yt-digest/test.sh checks
	# `[ -s "SKILL.md" ]` and reported the file missing when run from the repo
	# root, where that path means something else. The tests that already resolve
	# paths from BASH_SOURCE are unaffected.
	rc=0
	out="$(cd "$(dirname "$t")" && bash "$(basename "$t")" 2>&1)" || rc=$?
	if [ "$rc" -eq 0 ]; then
		printf '  %s: ok\n' "$skill"
	else
		failed=$((failed + 1)); names="$names $skill"
		printf '  %s: FAILED (exit %s)\n' "$skill" "$rc"
		# The whole output, not a tail. A skill test runs with set -e, so it can
		# end mid-way with no message at all, and then the last twelve lines are
		# its FIRST three: the reader sees two green ticks under the word FAILED
		# and learns nothing. Three release gates were diagnosed that way, or
		# rather were not. The cap is generous because a truncated failure report
		# is the expensive kind.
		printf '%s\n' "$out" | head -80 | sed 's/^/      /'
		_lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
		[ "$_lines" -gt 80 ] && printf '      ... %s more line(s)\n' "$((_lines - 80))"
		# The signal that costs the most to miss: a test that stopped rather than
		# reported. Its own summary line is the proof it reached the end.
		printf '%s\n' "$out" | grep -qE '[0-9]+ passed, [0-9]+ failed' \
			|| printf '      NOTE: no summary line, so the test ended early rather than reporting a failed assertion (set -e aborts silently)\n'
	fi
done < <(find system/skills vault/skills -mindepth 2 -maxdepth 2 -name test.sh 2>/dev/null | sort)

# A discovery loop that finds nothing looks exactly like a clean run. Say the
# denominator so an empty sweep cannot pass for a green one.
if [ "$ran" -eq 0 ]; then
	printf 'check-skill-tests: no skill tests found — did the skills move?\n' >&2
	exit 1
fi

if [ "$failed" -gt 0 ]; then
	printf 'check-skill-tests: %d of %d skill test(s) failed —%s\n' "$failed" "$ran" "$names"
	exit 1
fi
printf 'check-skill-tests: %d skill test(s) passed\n' "$ran"
