#!/usr/bin/env bash
# Validate session continuity documentation and local session file names when present.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0

# Public docs should use the collision-safe seconds + PID convention.
for file in system/sessions.md system/agent-config/shared.md; do
	if ! grep -q 'YYYYMMDD-HHMMSS-<pid>' "$file"; then
		printf 'Session schema doc missing HHMMSS PID convention: %s\n' "$file" >&2
		fail=1
	fi
	if grep -q 'YYYYMMDD-HHMM-<pid>' "$file"; then
		printf 'Session schema doc still references old HHMM PID convention: %s\n' "$file" >&2
		fail=1
	fi
done

# Validate private local archive names if local/ exists. This does not require local/ in CI.
if [[ -d local/sessions/archive ]]; then
	while IFS= read -r file; do
		base="$(basename "$file")"
		if ! [[ "$base" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}\.md$ ]]; then
			printf 'Invalid session archive filename: %s (expected YYYYMMDD-HHMMSS-<pid>.md)\n' "$file" >&2
			fail=1
		fi
	done < <(find local/sessions/archive -type f -name '*.md' | sort)
fi

if [[ -f local/sessions/session-journal.md ]]; then
	previous="$(grep -E '^previous:' local/sessions/session-journal.md | head -1 | sed 's/^previous:[[:space:]]*//')"
	if [[ -n "$previous" && ! "$previous" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$ ]]; then
		printf 'Invalid previous session reference: %s (expected YYYYMMDD-HHMMSS-<pid>)\n' "$previous" >&2
		fail=1
	fi
fi

if ((fail != 0)); then
	printf 'Session schema check failed.\n' >&2
	exit 1
fi

printf 'Session schema check passed.\n'
