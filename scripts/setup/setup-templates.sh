#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-templates.sh — Copy template and starter files.
# shellcheck disable=SC2034  # shared color/flag palette declared by convention; not every module uses every entry
# Safe to re-run (idempotent) — only creates missing files.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Render template substituting {{date}} and {{uuid5}} placeholders.
# UUID5 is deterministic per vault-relative path (matches uuid5-gen.sh +
# check-vault-content). Idempotent: same path → same id across re-runs.
# Args: $1=src template, $2=dest path, $3=vault-relative-path-no-ext for uuid5
render_template() {
	local src="$1" dest="$2" vault_rel="$3"
	local today uuid
	today="$(date +%F)"
	# Hard-fail on a uuid5 failure: a nil-UUID fallback would write notes whose id
	# the validate-hooks (uuid5 parity) reject later, which is far harder to trace.
	uuid="$(bash "${VAULT}/scripts/uuid5-gen.sh" "$vault_rel")" || {
		echo -e "${YELLOW}!${NC} uuid5-gen.sh failed for '${vault_rel}' — cannot render ${dest}." >&2
		echo "  Check python3 and brain.json (namespace), then re-run setup." >&2
		exit 1
	}
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
			# Two levels when the second segment names a real directory under the
			# first. vault/preferences is scoped (organization, team, personal)
			# and check-preference-scopes fails on any loose .md directly in it,
			# so a starter that belongs in a scope could not be seeded at all
			# with a single split.
			if [[ "$fname" == *-* ]] && [ -d "${VAULT}/vault/${subdir}/${fname%%-*}" ]; then
				subdir="${subdir}/${fname%%-*}"
				fname="${fname#*-}"
			fi
			dest="${VAULT}/vault/${subdir}/${fname}"
		else
			dest="${VAULT}/vault/${base}"
		fi
		if [ ! -f "$dest" ]; then
			mkdir -p "$(dirname "$dest")"
			# Compute vault-relative path without .md extension for uuid5
			vault_rel="${dest#"${VAULT}/"}"
			vault_rel="${vault_rel%.md}"
			render_template "$tmpl" "$dest" "$vault_rel"
			echo -e "${GREEN}Created${NC} local starter -> ${dest#"${VAULT}/"}"
		fi
	done
fi

# Migrate legacy flat local/preferences/*.md files into personal/ once
for pref in "${VAULT}/vault/preferences"/*.md; do
	[ -f "$pref" ] || continue
	base="$(basename "$pref")"
	dest="${VAULT}/vault/preferences/personal/${base}"
	if [ ! -f "$dest" ]; then
		mv "$pref" "$dest"
		echo -e "${GREEN}Migrated${NC} vault/preferences/${base} -> vault/preferences/personal/${base}"
	fi
done

# Seed personal preferences from public templates if missing
# Seeds for the vault live in templates/vault/<path>, mirroring local/<path>.
# Rendered once, never overwritten: the README that explains a directory, the
# empty project registry, the preference templates. They used to sit as
# vault-shaped directories in the checkout root (learnings/, projects/, …),
# which made the public tree look like a vault and invited real notes in.
SEEDS_DIR="${VAULT}/templates/vault"
if [ -d "$SEEDS_DIR" ]; then
	while IFS= read -r tmpl; do
		rel="${tmpl#"$SEEDS_DIR/"}"
		[ "$rel" = "preferences/personal/README.md" ] && continue
		dest="${VAULT}/vault/${rel}"
		[ -f "$dest" ] && continue
		mkdir -p "$(dirname "$dest")"
		case "$tmpl" in
		*.md) render_template "$tmpl" "$dest" "vault/${rel%.md}" ;;
		*) cp "$tmpl" "$dest" ;;
		esac
		echo -e "${GREEN}Created${NC} vault/${rel}"
	done < <(find "$SEEDS_DIR" -type f -not -name .DS_Store | sort)
fi
