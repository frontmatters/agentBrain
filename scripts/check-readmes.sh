#!/usr/bin/env bash
# Check that public markdown-bearing directories have README.md.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

missing=()
while IFS= read -r dir; do
	# If a directory contains markdown files directly, it should explain itself.
	if find "$dir" -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' | grep -q .; then
		if [[ ! -f "$dir/README.md" ]]; then
			missing+=("$dir")
		fi
	fi
done < <(
	find . -type d \
		-not -path './.git' -not -path './.git/*' \
		-not -path './local' -not -path './local/*' \
		-not -path './node_modules' -not -path './node_modules/*' \
		-not -path './.obsidian' -not -path './.obsidian/*' \
		-not -path './system/pi-config/extensions/.pi-lens' -not -path './system/pi-config/extensions/.pi-lens/*' \
		-not -path './system/addons/*' |
		sort
)

if ((${#missing[@]} > 0)); then
	printf 'README coverage failed. Missing README.md in:\n' >&2
	printf '  %s\n' "${missing[@]}" >&2
	exit 1
fi

printf 'README coverage passed.\n'
