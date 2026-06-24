#!/usr/bin/env bash
# Validate frontmatter for public agentBrain markdown notes.
# Templates and native GitHub skill manifests use their own schemas and are handled leniently.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0

is_exempt_template() {
	local file="$1"
	[[ "$file" == templates/*.md && "$file" != "templates/README.md" ]] && return 0
	[[ "$file" == templates/local-starters/*.md && "$file" != "templates/local-starters/README.md" ]] && return 0
	# user-preferences/*.md are source templates (with {{uuid5}}/{{date}} placeholders)
	# seeded by setup-templates.sh into local/preferences/personal/. They use the same
	# template-schema as templates/local-starters/ — exempt from strict id validation.
	[[ "$file" == user-preferences/*.md && "$file" != "user-preferences/README.md" ]] && return 0
	# Skill-owned templates live next to the skill (e.g. system/skills/scanman/templates/repro-spec/*.md).
	# They contain placeholder syntax (<name>, {{key}}) and are not vault notes. README.md inside the
	# template dir IS a real note and must keep frontmatter.
	if [[ "$file" == system/skills/*/templates/* ]] && [[ "$file" == *.md ]] && [[ "$(basename "$file")" != "README.md" ]]; then
		return 0
	fi
	return 1
}

is_skill_manifest() {
	[[ "$1" == system/skills/*/SKILL.md || "$1" == .github/skills/*/SKILL.md || "$1" == system/pi-config/skills/*/SKILL.md || "$1" == system/addons/*/SKILL.md ]]
}

check_has_frontmatter() {
	local file="$1"
	local first
	first="$(head -n 1 "$file" || true)"
	[[ "$first" == '---' ]]
}

frontmatter_block() {
	local file="$1"
	awk 'NR==1 && $0=="---" {in_fm=1; next} NR>1 && in_fm && $0=="---" {exit} in_fm {print}' "$file"
}

require_key() {
	local file="$1" key="$2" fm="$3"
	if ! grep -Eq "^${key}:" <<<"$fm"; then
		printf 'Missing %s in %s\n' "$key" "$file" >&2
		fail=1
	fi
}

validate_uuid() {
	local file="$1" fm="$2" id
	id="$(grep -E '^id:' <<<"$fm" | head -1 | sed 's/^id:[[:space:]]*//' || true)"
	if [[ -z "$id" ]]; then
		printf 'Missing id in %s\n' "$file" >&2
		fail=1
	elif ! [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
		printf 'Invalid UUID id in %s: %s\n' "$file" "$id" >&2
		fail=1
	fi
}

while IFS= read -r file; do
	# Ignore generated/local/private/third-party content. node_modules can be nested
	# (e.g. an add-on's own deps under system/addons/<id>/node_modules), so match at any depth.
	[[ "$file" == ./.git/* || "$file" == ./local/* || "$file" == *node_modules/* ]] && continue
	[[ "$file" == ./system/pi-config/extensions/.pi-lens/* ]] && continue
	# Operational state files from agent harnesses (Claude Code ralph-loop, etc.) are
	# not vault notes — they use their own runtime schemas, not the note frontmatter.
	[[ "$file" == ./.claude/* ]] && continue
	file="${file#./}"

	# Add-on manifests use the addon schema (validated by check-addons.sh), not note frontmatter.
	[[ "$file" == system/addons/*/manifest.md ]] && continue

	# GitHub special files (rendered on the repo / Security pages) conventionally
	# carry no YAML frontmatter — keep the public face clean. Only the ROOT ones;
	# nested README.md files are real notes and still need frontmatter.
	[[ "$file" == "README.md" || "$file" == "SECURITY.md" ]] && continue

	if is_exempt_template "$file"; then
		continue
	fi

	if ! check_has_frontmatter "$file"; then
		printf 'Missing frontmatter in %s\n' "$file" >&2
		fail=1
		continue
	fi

	fm="$(frontmatter_block "$file")"

	if is_skill_manifest "$file"; then
		require_key "$file" name "$fm"
		require_key "$file" description "$fm"
		continue
	fi

	require_key "$file" date "$fm"
	require_key "$file" type "$fm"
	require_key "$file" tags "$fm"
	validate_uuid "$file" "$fm"
done < <(find . -type f -name '*.md' | sort)

if ((fail != 0)); then
	printf 'Frontmatter check failed.\n' >&2
	exit 1
fi

printf 'Frontmatter check passed.\n'
