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
	if out="$(cd "$(dirname "$t")" && bash "$(basename "$t")" 2>&1)"; then
		printf '  %s: ok\n' "$skill"
	else
		failed=$((failed + 1)); names="$names $skill"
		printf '  %s: FAILED\n' "$skill"
		printf '%s\n' "$out" | tail -12 | sed 's/^/      /'
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
