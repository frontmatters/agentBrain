#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Lint stable prompt-prefix instructions for high-confidence volatile placeholders.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

files=()
if [ "$#" -gt 0 ]; then
	files=("$@")
else
	[ -f AGENTS.md ] && [ ! -L AGENTS.md ] && files+=(AGENTS.md)
	for file in \
		system/rules.md \
		system/llm-prompt-composition.md \
		system/agent-config/*.md \
		system/pi-config/agents.md \
		system/skills/*/SKILL.md; do
		[ -f "$file" ] && files+=("$file")
	done
fi

if [ "${#files[@]}" -eq 0 ]; then
	echo "check-prompt-cache-hygiene: no prompt sources found" >&2
	exit 1
fi

findings=0
for file in "${files[@]}"; do
	if [ ! -f "$file" ]; then
		echo "$file: missing prompt source" >&2
		findings=$((findings + 1))
		continue
	fi

	if ! output="$(awk '
		function report(label) { printf "%s:%d:%s\n", FILENAME, FNR, label }
		/^[[:space:]]*(```|~~~)/ { fenced = !fenced; next }
		fenced { next }
		{
			line = $0
			# Inline code is documentation, not an interpolated prompt value.
			gsub(/`[^`]*`/, "", line)
			if (line ~ /\$\([[:space:]]*date/) report("command-date")
			if (line ~ /\$\{(CURRENT_DATE|NOW|TIMESTAMP|REQUEST_ID|RANDOM)\}/ ||
			    line ~ /\$(CURRENT_DATE|NOW|TIMESTAMP|REQUEST_ID|RANDOM)([^A-Za-z0-9_]|$)/) report("volatile-shell-variable")
			if (line ~ /\{\{[[:space:]]*(current_date|timestamp|request_id)[[:space:]]*\}\}/) report("volatile-template-variable")
		}
	' "$file")"; then
		echo "$file: prompt lint failed to parse input" >&2
		exit 2
	fi
	while IFS= read -r finding; do
		[ -n "$finding" ] || continue
		printf '%s\n' "$finding" >&2
		findings=$((findings + 1))
	done <<< "$output"
done

if [ "$findings" -gt 0 ]; then
	echo "check-prompt-cache-hygiene: $findings volatile prompt placeholder(s) found" >&2
	exit 1
fi

echo "check-prompt-cache-hygiene: ${#files[@]} prompt source(s) passed"
