#!/usr/bin/env bash
# Claude PreCompact adapter for the extract-learnings behavior add-on.
# Reads {transcript_path,...} from stdin, extracts learnings, never blocks compaction.
# Contract: a missing dependency must be LOUD (a line to stderr), but the hook must
# still exit 0 so it never stalls or aborts compaction.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Incognito: read-only session → don't extract/persist learnings on compaction.
[ -f "$HERE/../incognito/is-incognito.sh" ] && bash "$HERE/../incognito/is-incognito.sh" && exit 0
payload="$(cat || true)"
tp="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || true)"
[ -n "$tp" ] && [ -f "$tp" ] || exit 0
# Loud-but-non-fatal: if bun is absent, say so on stderr and still exit 0. Never
# `|| true` the failure into silence.
if ! command -v bun >/dev/null 2>&1; then
  echo "extract-learnings: 'bun' not found on PATH — skipping learning extraction (install: https://bun.sh)" >&2
  exit 0
fi
# Bounded background run so compaction is never delayed; failures are non-fatal.
bun "$HERE/core.ts" "$tp" >/dev/null 2>&1 &
exit 0
