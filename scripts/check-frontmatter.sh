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

# Validate that a frontmatter block is well-formed YAML. Catches the classic
# "nested mappings not allowed in compact mappings" error that surfaces when a
# skill `description:` (or any scalar) contains an unquoted `: ` (colon+space),
# backtick-pairs, or other YAML-hostile text. The strict YAML agents (pi) reject
# such files; lax agents (Claude Code) load them silently — so the dev-time check
# here is what keeps the two in sync.
# We wrap the block in a single leading `---` (document-start marker) and use
# safe_load_all so the implicit trailing empty document doesn't trip us up —
# a trailing `---` would itself be a *start* marker and produce two docs.
validate_yaml_fm() {
	local file="$1" fm="$2"
	if ! command -v python3 >/dev/null 2>&1; then
		return 0  # soft-skip when python3 unavailable; not a hard dep of agentBrain
	fi
	local err
	err="$(printf -- '---\n%s' "$fm" | python3 -c 'import sys,yaml
try:
    list(yaml.safe_load_all(sys.stdin))
except Exception as e:
    print(str(e).splitlines()[0])
' 2>&1)"
	if [[ -n "$err" ]]; then
		printf 'Malformed YAML frontmatter in %s: %s\n' "$file" "$err" >&2
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
		validate_yaml_fm "$file" "$fm"
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
