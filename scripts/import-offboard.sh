#!/usr/bin/env bash
# import-offboard.sh — Import an agentBrain export package.
# Merges exported preferences, projects, daily notes, and learnings
# into the current agentBrain checkout without overwriting existing files.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

IMPORTED=0
SKIPPED=0

log_imported() {
	echo -e "${GREEN}Imported${NC} $1"
	IMPORTED=$((IMPORTED + 1))
}
log_skip() {
	echo -e "${YELLOW}Skip${NC}     $1 (already exists)"
	SKIPPED=$((SKIPPED + 1))
}

if [[ $# -ne 1 ]]; then
	echo "Usage: scripts/import-offboard.sh <export-file.tar.gz>"
	exit 1
fi

EXPORT_FILE="$1"

if [[ ! -f "$EXPORT_FILE" ]]; then
	echo "ERROR: file not found: $EXPORT_FILE" >&2
	exit 1
fi

if [[ ! -f "${VAULT}/brain.json" ]]; then
	echo "ERROR: brain.json not found. Run scripts/setup.sh first." >&2
	exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "agentBrain import"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Target: ${VAULT}"
echo "Source: ${EXPORT_FILE}"
echo ""

# ── 1. Extract ──────────────────────────────

EXTRACT_DIR="/tmp/agentBrain-import-$$"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$EXPORT_FILE" -C "$EXTRACT_DIR"

# Find the export root (may be wrapped in a directory)
EXPORT_ROOT=$(find "$EXTRACT_DIR" -name "meta" -type d -mindepth 1 -maxdepth 2 -exec dirname {} \; | head -1)
if [[ -z "$EXPORT_ROOT" ]]; then
	echo "ERROR: could not find export metadata. Is this a valid export?" >&2
	rm -rf "$EXTRACT_DIR"
	exit 1
fi

echo "Export metadata:"
if [[ -f "${EXPORT_ROOT}/meta/export-info.json" ]]; then
	cat "${EXPORT_ROOT}/meta/export-info.json"
fi
echo ""

# ── 2. Import preference scopes ─────────────

PREFS_SRC="${EXPORT_ROOT}/preferences"
PREFS_DST="${VAULT}/local/preferences"
if [[ -d "$PREFS_SRC" ]]; then
	mkdir -p "${PREFS_DST}/personal"
	# New scoped export format.
	for scope in personal team organization; do
		if [[ -d "${PREFS_SRC}/${scope}" ]]; then
			mkdir -p "${PREFS_DST}/${scope}"
			for f in "${PREFS_SRC}/${scope}"/*.md; do
				[[ -f "$f" ]] || continue
				BASE=$(basename "$f")
				if [[ -f "${PREFS_DST}/${scope}/${BASE}" ]]; then
					log_skip "preference/${scope}: ${BASE}"
				else
					cp "$f" "${PREFS_DST}/${scope}/${BASE}"
					log_imported "preference/${scope}: ${BASE}"
				fi
			done
		fi
	done
	# Backward compatibility: legacy flat exports import as personal scope.
	for f in "$PREFS_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		if [[ -f "${PREFS_DST}/personal/${BASE}" ]]; then
			log_skip "preference/personal: ${BASE}"
		else
			cp "$f" "${PREFS_DST}/personal/${BASE}"
			log_imported "preference/personal: ${BASE}"
		fi
	done
fi

# ── 3. Import project notes ─────────────────

PROJ_SRC="${EXPORT_ROOT}/projects"
PROJ_DST="${VAULT}/local/projects"
if [[ -d "$PROJ_SRC" ]]; then
	for proj_dir in "$PROJ_SRC"/*/; do
		[[ -d "$proj_dir" ]] || continue
		PROJ_NAME=$(basename "$proj_dir")
		mkdir -p "${PROJ_DST}/${PROJ_NAME}"
		for f in "${proj_dir}"*.md; do
			[[ -f "$f" ]] || continue
			BASE=$(basename "$f")
			if [[ -f "${PROJ_DST}/${PROJ_NAME}/${BASE}" ]]; then
				log_skip "project/${PROJ_NAME}/${BASE}"
			else
				cp "$f" "${PROJ_DST}/${PROJ_NAME}/${BASE}"
				log_imported "project/${PROJ_NAME}/${BASE}"
			fi
		done
	done
fi

# ── 4. Import daily notes ───────────────────

DAILY_SRC="${EXPORT_ROOT}/daily-notes"
DAILY_DST="${VAULT}/local/daily-notes"
if [[ -d "$DAILY_SRC" ]]; then
	mkdir -p "$DAILY_DST"
	for f in "$DAILY_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		if [[ -f "${DAILY_DST}/${BASE}" ]]; then
			log_skip "daily-note: ${BASE}"
		else
			cp "$f" "${DAILY_DST}/${BASE}"
			log_imported "daily-note: ${BASE}"
		fi
	done
fi

# ── 5. Import learnings ─────────────────────

LEARN_SRC="${EXPORT_ROOT}/learnings"
LEARN_DST="${VAULT}/local/learnings"
if [[ -d "$LEARN_SRC" ]]; then
	mkdir -p "$LEARN_DST"
	for f in "$LEARN_SRC"/*.md; do
		[[ -f "$f" ]] || continue
		BASE=$(basename "$f")
		if [[ -f "${LEARN_DST}/${BASE}" ]]; then
			log_skip "learning: ${BASE}"
		else
			cp "$f" "${LEARN_DST}/${BASE}"
			log_imported "learning: ${BASE}"
		fi
	done
	# Extracted learnings
	if [[ -d "${LEARN_SRC}/extracted" ]]; then
		mkdir -p "${LEARN_DST}/extracted"
		for f in "${LEARN_SRC}/extracted"/*.md; do
			[[ -f "$f" ]] || continue
			BASE=$(basename "$f")
			if [[ -f "${LEARN_DST}/extracted/${BASE}" ]]; then
				log_skip "learning/extracted: ${BASE}"
			else
				cp "$f" "${LEARN_DST}/extracted/${BASE}"
				log_imported "learning/extracted: ${BASE}"
			fi
		done
	fi
fi

# ── 6. Import sessions, reports, memories, research ──

EXTRA_DIRS=("sessions" "reports" "memories" "research")
for subdir in "${EXTRA_DIRS[@]}"; do
	SRC="${EXPORT_ROOT}/${subdir}"
	DST="${VAULT}/local/${subdir}"
	if [[ -d "$SRC" ]]; then
		mkdir -p "$DST"
		COUNT=0
		for f in "$SRC"/*.md; do
			[[ -f "$f" ]] || continue
			BASE=$(basename "$f")
			if [[ -f "${DST}/${BASE}" ]]; then
				log_skip "${subdir}/${BASE}"
			else
				cp "$f" "${DST}/${BASE}"
				log_imported "${subdir}/${BASE}"
				COUNT=$((COUNT + 1))
			fi
		done
	fi
done

# ── 6b. Restore addon config ────────────────
# Copy registry config back (without overwriting); report enabled addons + locale
# as manual re-apply steps (re-enabling runs install logic with side effects).
CONFIG_SRC="${EXPORT_ROOT}/config"
if [[ -d "$CONFIG_SRC" ]]; then
	mkdir -p "${VAULT}/local/addons"
	for cfg in registries.json default-url; do
		if [[ -f "${CONFIG_SRC}/${cfg}" ]]; then
			if [[ -f "${VAULT}/local/addons/${cfg}" ]]; then
				log_skip "config/${cfg}"
			else
				cp "${CONFIG_SRC}/${cfg}" "${VAULT}/local/addons/${cfg}"
				log_imported "config/${cfg}"
			fi
		fi
	done
	if [[ -s "${CONFIG_SRC}/enabled-addons.txt" ]]; then
		echo ""
		echo "Enabled addons in the export (re-enable manually — installs may have side effects):"
		while IFS= read -r _id; do
			[[ -n "$_id" ]] && echo "    bash scripts/addons.sh install ${_id}"
		done < "${CONFIG_SRC}/enabled-addons.txt"
	fi
	if [[ -s "${CONFIG_SRC}/locale.txt" ]]; then
		echo "Exported locale: $(cat "${CONFIG_SRC}/locale.txt") — set via /onboard locale or your shell rc."
	fi
fi

# ── 7. Cleanup ──────────────────────────────

rm -rf "$EXTRACT_DIR"

# ── 7. Validate ─────────────────────────────

echo ""
echo "Running doctor..."
(cd "$VAULT" && bash scripts/doctor.sh --summary) || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Import complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Imported: ${IMPORTED}"
echo "  Skipped:  ${SKIPPED} (already existed)"
echo ""
echo "  Next steps:"
echo "    1. Review imported personal preferences: ls local/preferences/personal/"
echo "    2. Run /onboard to update any preferences"
echo "    3. Start coding!"
