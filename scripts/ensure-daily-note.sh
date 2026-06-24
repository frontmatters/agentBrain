#!/usr/bin/env bash
# ensure-daily-note.sh — guarantee a daily‑note exists for today.
# Idempotent – creates the file only if missing and copies from the template.

set -euo pipefail

# Resolve vault root (the repository root). If called from any sub‑dir, use the environment variable set by other scripts.
VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
NOTE_DIR="${VAULT}/local/daily-notes"
TEMPLATE="${VAULT}/templates/daily.md"
TODAY=$(date +%F)
NOTE="${NOTE_DIR}/${TODAY}.md"

# Ensure the container directory exists.
mkdir -p "${NOTE_DIR}"

if [[ -f "${NOTE}" ]]; then
	echo "Daily note already exists: ${NOTE}"
	exit 0
fi

if [[ -f "${TEMPLATE}" ]]; then
	# Render template: substitute {{date}} and {{uuid5}} placeholders.
	# UUID5 is deterministic per vault-relative path (matches uuid5-gen.sh + check-local-content).
	UUID=$(bash "${VAULT}/scripts/uuid5-gen.sh" "local/daily-notes/${TODAY}")
	sed -e "s|{{date}}|${TODAY}|g" -e "s|{{uuid5}}|${UUID}|g" "${TEMPLATE}" > "${NOTE}"
	echo "Created daily note from template: ${NOTE}"
else
	# Fallback minimal content if template missing.
	UUID=$(bash "${VAULT}/scripts/uuid5-gen.sh" "local/daily-notes/${TODAY}" 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")
	cat > "${NOTE}" <<-EOF
		---
		date: ${TODAY}
		type: daily
		tags: [daily]
		id: ${UUID}
		---

		# Daily note ${TODAY}
	EOF
	echo "Created minimal daily note: ${NOTE}"
fi
