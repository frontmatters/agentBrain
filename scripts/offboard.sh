#!/usr/bin/env bash
# offboard.sh — Export agentBrain knowledge and preferences for transfer.
# Produces a portable .tar.gz that can be imported on another machine.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EXPORT_NAME="agentBrain-export-${TIMESTAMP}"
EXPORT_DIR="/tmp/${EXPORT_NAME}"
EXPORT_FILE="${HOME}/${EXPORT_NAME}.tar.gz"
GPG_MODE=""
GPG_KEY=""

ALL_DAILY=false
INCLUDE_TEAM=false
INCLUDE_ORG=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--all) ALL_DAILY=true ;;
	--include-team) INCLUDE_TEAM=true ;;
	--include-organization) INCLUDE_ORG=true ;;
	--encrypt) GPG_MODE="symmetric" ;;
	--encrypt=*) GPG_MODE="recipient"; GPG_KEY="${1#--encrypt=}" ;;
	-h | --help)
		echo "Usage: scripts/offboard.sh [--all] [--include-team] [--include-organization] [--encrypt[=KEY]]"
		echo "  --all                   Export all daily notes instead of the last 90 days"
		echo "  --include-team          Include local/preferences/team/ in the export"
		echo "  --include-organization  Include local/preferences/organization/ in the export"
		echo "  --encrypt               GPG-encrypt the export (symmetric; prompts for a passphrase)"
		echo "  --encrypt=KEY           GPG-encrypt for the given recipient key id"
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
	shift
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "agentBrain offboard export"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Source: ${VAULT}"
echo ""

# Validate source
if [[ ! -f "${VAULT}/brain.json" ]]; then
	echo "ERROR: brain.json not found. Is this an agentBrain checkout?" >&2
	exit 1
fi

# ── 1. Doctor check ─────────────────────────

echo "Running doctor..."
(cd "$VAULT" && bash scripts/doctor.sh --summary) || true
echo ""

# ── 2. Create export structure ──────────────

rm -rf "$EXPORT_DIR"
mkdir -p "${EXPORT_DIR}/preferences/personal"
mkdir -p "${EXPORT_DIR}/projects"
mkdir -p "${EXPORT_DIR}/daily-notes"
mkdir -p "${EXPORT_DIR}/learnings"
mkdir -p "${EXPORT_DIR}/meta"

# ── 3. Export preference scopes ─────────────

PREF_COUNT=0
PERSONAL_PREFS_SRC="${VAULT}/local/preferences/personal"
LEGACY_PREFS_SRC="${VAULT}/local/preferences"
if [[ -d "$PERSONAL_PREFS_SRC" ]]; then
	for f in "$PERSONAL_PREFS_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		cp "$f" "${EXPORT_DIR}/preferences/personal/${BASE}"
		PREF_COUNT=$((PREF_COUNT + 1))
	done
elif [[ -d "$LEGACY_PREFS_SRC" ]]; then
	# Backward compatibility: legacy flat preferences are exported as personal scope.
	for f in "$LEGACY_PREFS_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		cp "$f" "${EXPORT_DIR}/preferences/personal/${BASE}"
		PREF_COUNT=$((PREF_COUNT + 1))
	done
fi

if [[ "$INCLUDE_TEAM" == true && -d "${VAULT}/local/preferences/team" ]]; then
	mkdir -p "${EXPORT_DIR}/preferences/team"
	for f in "${VAULT}/local/preferences/team"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		cp "$f" "${EXPORT_DIR}/preferences/team/${BASE}"
		PREF_COUNT=$((PREF_COUNT + 1))
	done
fi

if [[ "$INCLUDE_ORG" == true && -d "${VAULT}/local/preferences/organization" ]]; then
	mkdir -p "${EXPORT_DIR}/preferences/organization"
	for f in "${VAULT}/local/preferences/organization"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		cp "$f" "${EXPORT_DIR}/preferences/organization/${BASE}"
		PREF_COUNT=$((PREF_COUNT + 1))
	done
fi

if [[ "$PREF_COUNT" -gt 0 ]]; then
	echo -e "${GREEN}Exported${NC} ${PREF_COUNT} preference files"
else
	echo -e "${YELLOW}Skip${NC}    preferences (none found)"
fi

# ── 4. Export project notes ─────────────────

PROJ_SRC="${VAULT}/local/projects"
if [[ -d "$PROJ_SRC" ]]; then
	PROJ_COUNT=0
	for proj_dir in "$PROJ_SRC"/*/; do
		[[ -d "$proj_dir" ]] || continue
		PROJ_NAME=$(basename "$proj_dir")
		mkdir -p "${EXPORT_DIR}/projects/${PROJ_NAME}"
		cp -r "${proj_dir}"*.md "${EXPORT_DIR}/projects/${PROJ_NAME}/" 2>/dev/null || true
		PROJ_COUNT=$((PROJ_COUNT + 1))
	done
	echo -e "${GREEN}Exported${NC} ${PROJ_COUNT} project note directories"
else
	echo -e "${YELLOW}Skip${NC}    projects"
fi

# ── 5. Export daily notes (last 90 days) ────

DAILY_SRC="${VAULT}/local/daily-notes"
if [[ -d "$DAILY_SRC" ]]; then
	NOTE_COUNT=0
	if [[ "$ALL_DAILY" == true ]]; then
		for note in "$DAILY_SRC"/*.md; do
			[[ -f "$note" ]] || continue
			cp "$note" "${EXPORT_DIR}/daily-notes/"
			NOTE_COUNT=$((NOTE_COUNT + 1))
		done
		echo -e "${GREEN}Exported${NC} ${NOTE_COUNT} daily notes (all)"
	else
		CUTOFF=$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d 2>/dev/null || echo "2020-01-01")
		for note in "$DAILY_SRC"/*.md; do
			[[ -f "$note" ]] || continue
			NOTE_DATE=$(basename "$note" .md)
			if [[ "$NOTE_DATE" > "$CUTOFF" ]] || [[ "$NOTE_DATE" == "$CUTOFF" ]]; then
				cp "$note" "${EXPORT_DIR}/daily-notes/"
				NOTE_COUNT=$((NOTE_COUNT + 1))
			fi
		done
		echo -e "${GREEN}Exported${NC} ${NOTE_COUNT} daily notes (last 90 days, use --all for everything)"
	fi
else
	echo -e "${YELLOW}Skip${NC}    daily notes"
fi

# ── 6. Export learnings ─────────────────────

LEARNS_SRC="${VAULT}/local/learnings"
if [[ -d "$LEARNS_SRC" ]]; then
	LEARN_COUNT=0
	for f in "$LEARNS_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		cp "$f" "${EXPORT_DIR}/learnings/"
		LEARN_COUNT=$((LEARN_COUNT + 1))
	done
	# Also extracted learnings
	if [[ -d "${LEARNS_SRC}/extracted" ]]; then
		mkdir -p "${EXPORT_DIR}/learnings/extracted"
		for f in "${LEARNS_SRC}/extracted"/*.md; do
			[[ -f "$f" ]] || continue
			cp "$f" "${EXPORT_DIR}/learnings/extracted/"
			LEARN_COUNT=$((LEARN_COUNT + 1))
		done
	fi
	echo -e "${GREEN}Exported${NC} ${LEARN_COUNT} learning notes"
else
	echo -e "${YELLOW}Skip${NC}    learnings"
fi

# ── 7. Export sessions, reports, memories, research ──

EXTRA_DIRS=("sessions" "reports" "memories" "research")
for subdir in "${EXTRA_DIRS[@]}"; do
	SRC="${VAULT}/local/${subdir}"
	if [[ -d "$SRC" ]]; then
		COUNT=$(find "$SRC" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
		if [[ "$COUNT" -gt 0 ]]; then
			mkdir -p "${EXPORT_DIR}/${subdir}"
			cp -r "${SRC}"/*.md "${EXPORT_DIR}/${subdir}/" 2>/dev/null || true
			echo -e "${GREEN}Exported${NC} ${COUNT} ${subdir} files"
		else
			echo -e "${YELLOW}Skip${NC}    ${subdir} (empty)"
		fi
	else
		echo -e "${YELLOW}Skip${NC}    ${subdir}"
	fi
done

# ── 7b. Export addon config (registries + enabled addons) ──
# Portable machine config: the default registry pointer, named registries, and
# which addons are enabled. Restored by import-offboard.sh without overwriting.
mkdir -p "${EXPORT_DIR}/config"
for cfg in registries.json default-url; do
	if [[ -f "${VAULT}/local/addons/${cfg}" ]]; then
		cp "${VAULT}/local/addons/${cfg}" "${EXPORT_DIR}/config/${cfg}"
	fi
done
# Enabled addons, one id per line.
if [[ -d "${VAULT}/local/addons" ]]; then
	for marker in "${VAULT}/local/addons"/*/enabled; do
		[[ -f "$marker" ]] || continue
		basename "$(dirname "$marker")"
	done > "${EXPORT_DIR}/config/enabled-addons.txt"
fi
# Locale, best-effort (env or shell-rc export).
{ [[ -n "${AGENTBRAIN_LOCALE:-}" ]] && echo "$AGENTBRAIN_LOCALE"; } > "${EXPORT_DIR}/config/locale.txt" 2>/dev/null || true

# ── 8. Export metadata ──────────────────────

cp "${VAULT}/brain.json" "${EXPORT_DIR}/meta/brain.json"

cat >"${EXPORT_DIR}/meta/export-info.json" <<EOF
{
  "exportedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "sourcePath": "${VAULT}",
  "version": "$(cat "${VAULT}/VERSION" 2>/dev/null || echo 'unknown')",
  "platform": "$(uname -s)"
}
EOF

cat >"${EXPORT_DIR}/README.md" <<'README'
# agentBrain Export Package

This package contains exported agentBrain data for transfer to another machine.

## Import instructions

1. Install agentBrain on the new machine:
   ```bash
   git clone <repo> ~/Developer/agentBrain
   cd ~/Developer/agentBrain && bash scripts/setup.sh
   ```

2. Import this export:
   ```bash
   bash scripts/import-offboard.sh /path/to/agentBrain-export-XXXXXXXX-XXXXXX.tar.gz
   ```

3. Run doctor to validate:
   ```bash
   bash scripts/doctor.sh --summary
   ```

## Contents

- `preferences/personal/` — Personal preference scope files
- `preferences/team/` — Team preference scope files (only when exported with `--include-team`)
- `preferences/organization/` — Organization preference scope files (only when exported with `--include-organization`)
- `projects/` — Project notes (one subdirectory per project)
- `daily-notes/` — Recent daily notes (last 90 days)
- `learnings/` — Learning notes and extracted learnings
- `sessions/` — Session logs
- `reports/` — Reports
- `memories/` — Personal agent context
- `research/` — Research notes
- `config/` — addon registries (`registries.json`, `default-url`), `enabled-addons.txt`, `locale.txt`
- `meta/` — brain.json and export metadata
README

# ── 8. Privacy scan on export ───────────────

echo ""
echo "Running privacy scan on export..."
# Check for obvious secrets in exported files
SECRET_HITS=0
while IFS= read -r -d '' f; do
	if grep -qiE '(api.key|secret|token|password|credential).{0,20}(sk-|ghp_|gho_|xox[bpas]-|AKIA|AIza)' "$f" 2>/dev/null; then
		rel="${f#"$EXPORT_DIR"/}"
		echo "  ⚠️  Potential secret in: ${rel}"
		SECRET_HITS=$((SECRET_HITS + 1))
	fi
done < <(find "$EXPORT_DIR" -name '*.md' -print0 -o -name '*.json' -print0 2>/dev/null)
if [[ $SECRET_HITS -gt 0 ]]; then
	echo -e "${YELLOW}Warning${NC} ${SECRET_HITS} files may contain secrets. Review before sharing."
fi

# ── 9. Package ──────────────────────────────

tar -czf "$EXPORT_FILE" -C /tmp "$EXPORT_NAME"
rm -rf "$EXPORT_DIR"

# Optional GPG encryption — the tarball holds the entire private layer in
# plaintext; once it lands in $HOME it is exposed to Time Machine/cloud sync.
if [[ -n "$GPG_MODE" ]]; then
	if ! command -v gpg >/dev/null 2>&1; then
		echo "ERROR: --encrypt requested but gpg is not installed (brew install gnupg). Plain export kept at $EXPORT_FILE" >&2
		exit 1
	fi
	if [[ "$GPG_MODE" == "recipient" ]]; then
		gpg --yes --recipient "$GPG_KEY" --encrypt "$EXPORT_FILE"
	else
		gpg --yes --symmetric --cipher-algo AES256 "$EXPORT_FILE"
	fi
	rm "$EXPORT_FILE"
	EXPORT_FILE="${EXPORT_FILE}.gpg"
else
	echo ""
	echo "Note: export is NOT encrypted — it contains your full private layer."
	echo "Use --encrypt (passphrase) or --encrypt=KEYID before moving it to cloud/USB."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Export complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  File:     ${EXPORT_FILE}"
echo "  Size:     $(du -h "$EXPORT_FILE" | cut -f1)"
echo ""
echo "  To import on another machine:"
echo "    bash scripts/import-offboard.sh ${EXPORT_NAME}.tar.gz"
