#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Derive a project-slug from a ~/.claude/projects/<encoded>/ directory.
# Strategy: read the cwd from any transcript JSONL in that dir, take basename.
# Fallback: convert the encoded-cwd dirname (best-effort).
# Usage: slug.sh <claude-projects-encoded-dir>
set -euo pipefail

project_dir="${1:-}"
if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
	echo "usage: slug.sh <claude-projects-dir>" >&2
	exit 2
fi

# Try a JSONL transcript first.
slug=""
transcript=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1 || true)
if [[ -n "$transcript" && -f "$transcript" ]]; then
	cwd="$(python3 -c "
import json,sys
with open('$transcript', encoding='utf-8', errors='replace') as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('cwd'):
                print(d['cwd']); break
        except Exception: continue
" 2>/dev/null || true)"
	if [[ -n "$cwd" ]]; then
		# Basename, lowercased, replace spaces/_ with -, strip non-portable chars.
		slug="$(basename "$cwd" | tr '[:upper:] _' '[:lower:]--' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g')"
	fi
fi

# Fallback: derive from encoded-cwd dirname.
if [[ -z "$slug" ]]; then
	encoded="$(basename "$project_dir")"
	# Take everything after the last '-' run as the slug.
	slug="$(printf '%s' "$encoded" | awk -F'-' '{print $NF}' | tr '[:upper:]' '[:lower:]')"
fi

# Last-resort sanitization.
slug="${slug:-unknown}"
printf '%s\n' "$slug"
