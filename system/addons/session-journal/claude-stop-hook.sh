#!/usr/bin/env bash
# Claude Code Stop hook adapter for session-journal.
# Reads {transcript_path,...} JSON on stdin, runs journal-update in the background,
# always exits 0 so Claude Code is never blocked by us.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Incognito: read-only session → don't write the journal at session end.
[ -f "$HERE/../incognito/is-incognito.sh" ] && bash "$HERE/../incognito/is-incognito.sh" && exit 0

payload="$(cat || true)"
if [[ -z "$payload" ]]; then
	exit 0
fi

# Run detached so a slow/dead parse can never delay session end.
(
	printf '%s' "$payload" | bash "$HERE/journal-update.sh" --stdin --source stop
) >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
