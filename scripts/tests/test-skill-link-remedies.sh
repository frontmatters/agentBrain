#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-skill-link-remedies.sh — a failing check must name a command that can
# actually fix it.
#
# The regression: check-skill-links.sh reported "skills dir missing — run: bash
# scripts/setup/setup-skills.sh" for every agent, including Pi. setup-skills.sh
# contains no reference to pi; its own header says "Pi is handled by
# configure-pi.sh". A user with an unconfigured Pi ran the named script, nothing
# changed, and the check failed again with the same advice.
#
# So the invariant is not "the message mentions a script". It is: run the script
# the check names, in a clean HOME where that agent is present, and the missing
# directory exists afterwards. A remedy that cannot produce the directory is a
# dead end no matter how plausible it reads.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-skill-remedies.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

CHECK="$ROOT_DIR/scripts/checks/check-skill-links.sh"

# Read the agent table out of the check itself, so a new agent row is covered
# the moment it is added rather than when someone remembers to extend this file.
rows="$(sed -n '/^AGENTS=(/,/^)/p' "$CHECK" | grep '^\s*"' | tr -d '\t"')"
[ -n "$rows" ] || { bad "could not read the AGENTS table from check-skill-links.sh"; printf 'skill-link-remedies: 0 passed, 1 failed\n'; exit 1; }

n_rows=0
while IFS='|' read -r _dir cli skills_tpl label remedy; do
	[ -n "${label:-}" ] || continue
	n_rows=$((n_rows + 1))

	# Every row must carry a remedy. A blank field would silently print
	# "run: " and send the user nowhere.
	if [ -z "${remedy:-}" ]; then
		bad "$label has no repair command"
		continue
	fi

	# The named script must exist. A remedy pointing at a moved or renamed
	# script is the same dead end as one pointing at the wrong script.
	script="${remedy##* }"
	if [ ! -f "$ROOT_DIR/$script" ]; then
		bad "$label names a script that does not exist: $script"
		continue
	fi

	# The real assertion: does that script create this agent's skills dir?
	home="$TMP/$label"; home="${home// /-}"
	mkdir -p "$home/bin" "$(eval echo "${_dir/\$\{AGENT_HOME\}/$home}")"
	printf '#!/bin/sh\necho 1.0.0\n' > "$home/bin/$cli"
	chmod +x "$home/bin/$cli"

	skills_dir="$(eval echo "${skills_tpl/\$\{AGENT_HOME\}/$home}")"
	[ -d "$skills_dir" ] && { bad "$label fixture started with the skills dir already present"; continue; }

	# BRAIN_ALIAS pins the source brain to this checkout. Without it the setup
	# scripts derive it as $AGENT_HOME/agentBrain, which inside a fixture HOME
	# does not exist, and every link they create dangles.
	#
	# That makes the checkout writable from inside the fixture, and
	# configure-pi.sh does write one file there: it renders
	# system/pi-config/extensions/tsconfig.json from a template, substituting
	# the Pi module paths it found. Under this fixture's PATH it finds
	# different ones, so the run left a tsconfig behind that no longer type
	# checks, and check-pi-extension-types failed on the next doctor. The file
	# is gitignored, so `git status` showed nothing.
	#
	# PI_CONFIG_SOURCE redirects that write into a copy. Everything else the
	# scripts touch in the checkout is read-only.
	cp -R "$ROOT_DIR/system/pi-config" "$home/pi-config"
	#
	# PATH carries only the fixture bin plus the system dirs. Appending the real
	# PATH lets the machine's own agents leak in, and the script then configures
	# the wrong one: a run meant to exercise Copilot found the real claude and
	# wrote to a Claude fixture instead.
	HOME="$home" AGENTBRAIN_HOME="$home" BRAIN_ALIAS="$ROOT_DIR" \
		PI_CONFIG_DIR="$home/.pi/agent" PI_CONFIG_SOURCE="$home/pi-config" \
		PATH="$home/bin:/usr/bin:/bin:/usr/sbin" \
		bash "$ROOT_DIR/$script" >"$home/out.log" 2>&1

	if [ -d "$skills_dir" ]; then
		ok "$label: '$remedy' creates $(basename "$(dirname "$skills_dir")")/skills"
	else
		bad "$label: '$remedy' ran but did not create $skills_dir (see $home/out.log)"
	fi
done <<< "$rows"

# Never report a verdict without a denominator: a table this loop failed to
# parse would otherwise pass with zero assertions made.
[ "$n_rows" -ge 3 ] \
	&& ok "all $n_rows agent rows examined" \
	|| bad "expected at least 3 agent rows, parsed $n_rows"

printf 'skill-link-remedies: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
