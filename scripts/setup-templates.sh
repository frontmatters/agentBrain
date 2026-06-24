#!/usr/bin/env bash
# setup-templates.sh — Copy template and starter files.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Safe to re-run (idempotent) — only creates missing files.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Render template substituting {{date}} and {{uuid5}} placeholders.
# UUID5 is deterministic per vault-relative path (matches uuid5-gen.sh +
# check-local-content). Idempotent: same path → same id across re-runs.
# Args: $1=src template, $2=dest path, $3=vault-relative-path-no-ext for uuid5
render_template() {
	local src="$1" dest="$2" vault_rel="$3"
	local today uuid
	today="$(date +%F)"
	uuid="$(bash "${VAULT}/scripts/uuid5-gen.sh" "$vault_rel" 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")"
	sed -e "s|{{date}}|${today}|g" -e "s|{{uuid5}}|${uuid}|g" "$src" > "$dest"
}

# Copy local-starter templates (only if target file doesn't exist yet)
STARTERS_DIR="${VAULT}/templates/local-starters"
if [ -d "$STARTERS_DIR" ]; then
	for tmpl in "$STARTERS_DIR"/*.md; do
		[ -e "$tmpl" ] || continue
		base="$(basename "$tmpl")"
		if [[ "$base" == *-* ]]; then
			subdir="${base%%-*}"
			fname="${base#*-}"
			dest="${VAULT}/local/${subdir}/${fname}"
		else
			dest="${VAULT}/local/${base}"
		fi
		if [ ! -f "$dest" ]; then
			mkdir -p "$(dirname "$dest")"
			# Compute vault-relative path without .md extension for uuid5
			vault_rel="${dest#"${VAULT}/"}"
			vault_rel="${vault_rel%.md}"
			render_template "$tmpl" "$dest" "$vault_rel"
			echo -e "${GREEN}Created${NC} local starter -> ${dest##*/VAULT/}"
		fi
	done
fi

# Migrate legacy flat local/preferences/*.md files into personal/ once
for pref in "${VAULT}/local/preferences"/*.md; do
	[ -f "$pref" ] || continue
	base="$(basename "$pref")"
	dest="${VAULT}/local/preferences/personal/${base}"
	if [ ! -f "$dest" ]; then
		mv "$pref" "$dest"
		echo -e "${GREEN}Migrated${NC} local/preferences/${base} -> local/preferences/personal/${base}"
	fi
done

# Seed personal preferences from public templates if missing
if [ -d "${VAULT}/user-preferences" ]; then
	for tmpl in "${VAULT}/user-preferences"/*.md; do
		[ -e "$tmpl" ] || continue
		base="$(basename "$tmpl")"
		[ "$base" = "README.md" ] && continue
		dest="${VAULT}/local/preferences/personal/${base}"
		if [ ! -f "$dest" ]; then
			vault_rel="local/preferences/personal/${base%.md}"
			render_template "$tmpl" "$dest" "$vault_rel"
			echo -e "${GREEN}Created${NC} personal preference template -> ${base}"
		fi
	done
fi
