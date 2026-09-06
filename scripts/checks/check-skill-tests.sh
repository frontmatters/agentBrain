#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-skill-tests.sh — Auto-discover and run per-skill test suites.
#
# Convention: a skill MAY ship a `test.sh` at the root of its folder
# (`local/skills/<name>/test.sh` or `system/skills/<name>/test.sh`).
# Doctor will execute it during a full health check.
#
# Contract for skill authors:
#   - test.sh is executed with cwd set to its own skill folder.
#   - test.sh should exit 0 on success, non-zero on failure.
#   - test.sh should be idempotent (no leftover state) and self-cleaning.
#   - Output: silent on success preferred; verbose on failure.
#
# This validator is opt-in: skills without test.sh are NOT flagged.
# Adding test.sh is the recommended way to defend against skill regressions
# without bloating the central doctor.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

fail=0
ran=0
flaky=0
skipped_skills=0

run_skill_test() {
	local test_file="$1"
	local skill_dir
	skill_dir="$(dirname "$test_file")"
	local skill_name
	skill_name="$(basename "$skill_dir")"
	local scope
	scope="$(basename "$(dirname "$skill_dir")")"     # "skills"
	local layer
	layer="$(basename "$(dirname "$(dirname "$skill_dir")")")"  # "local" or "system"

	ran=$((ran + 1))
	# mktemp avoids predictable /tmp name (symlink-clobber footgun caught by Pi review).
	# trap ensures cleanup even on Ctrl-C or unexpected exit.
	local log_file
	log_file="$(mktemp "${TMPDIR:-/tmp}/check-skill-test.XXXXXX")"
	# shellcheck disable=SC2064  # we want $log_file expanded NOW, not on trigger
	trap "rm -f '$log_file'" RETURN

	# Run in subshell so a `set -e` or `cd` inside test.sh can't leak out.
	if ( cd "$skill_dir" && bash test.sh ) >"$log_file" 2>&1; then
		echo "  ✓ $layer/$scope/$skill_name"
		return 0
	fi
	# A failure keeps its evidence. Doctor's --summary shows only the line that
	# says "failed", and the temp log used to be gone by then; peer-review
	# failed once in a release check and nothing was left to read. The log now
	# survives at a fixed path named in that one line, and the test runs once
	# more: a pass on retry is reported as flaky, not as green.
	local kept="${TMPDIR:-/tmp}/agentbrain-skill-test-${skill_name}.log"
	cp "$log_file" "$kept"
	if ( cd "$skill_dir" && bash test.sh ) >"$log_file" 2>&1; then
		echo "  ⚠ $layer/$scope/$skill_name — test.sh failed once, passed on retry (flaky; first log: $kept)" >&2
		flaky=$((flaky + 1))
	else
		echo "  ✗ $layer/$scope/$skill_name — test.sh failed twice (log: $kept)" >&2
		echo "  Last 20 lines:" >&2
		tail -n 20 "$log_file" | sed 's/^/    /' >&2
		fail=1
	fi
}

# Count skills without test.sh (informational, not failure).
count_skills_without_tests() {
	local pattern="$1"
	local count=0
	while IFS= read -r -d '' skill_dir; do
		[ -f "$skill_dir/test.sh" ] || count=$((count + 1))
	done < <(find "$pattern" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
	echo "$count"
}

# Use find with trailing slash to follow `local/` symlink (agentBrain convention).
while IFS= read -r -d '' test_file; do
	run_skill_test "$test_file"
done < <(find vault/skills/ system/skills/ -mindepth 2 -maxdepth 2 -type f -name 'test.sh' -print0 2>/dev/null)

local_skills_without=$(count_skills_without_tests 'vault/skills/')
system_skills_without=$(count_skills_without_tests 'system/skills/')
skipped_skills=$((local_skills_without + system_skills_without))

if [ "$fail" -ne 0 ]; then
	echo "check-skill-tests: ❌ at least one skill test failed" >&2
	exit 1
fi

[ "${flaky:-0}" -gt 0 ] && echo "check-skill-tests: ⚠ $flaky skill test(s) flaky (failed once, passed on retry); logs kept in ${TMPDIR:-/tmp}/agentbrain-skill-test-*.log" >&2
echo "check-skill-tests: ✅ $ran skill test.sh ran, $skipped_skills skill(s) without test.sh (opt-in convention)"
exit 0
