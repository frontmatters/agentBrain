#!/usr/bin/env bash
# package-addon.sh — Build a distributable zip for one addon.
# Usage: bash scripts/package-addon.sh <id> [--out <dir>] [--roots <dir:dir>]
# Looks up the addon (default: system/addons then local/addons), stages a
# clean copy (no state/log artefacts), privacy-scans the payload, then zips
# it as addon-<id>-v<version>.zip with a .sha256 file next to it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${1:?usage: package-addon.sh <id> [--out <dir>] [--roots <dir:dir>]}"
shift || true
OUT_DIR="${OUT_DIR:-$ROOT/../agentBrain-releases/addons}"
ROOTS="$ROOT/system/addons:$ROOT/local/addons"

while [ $# -gt 0 ]; do
	case "$1" in
		--out)   OUT_DIR="$2"; shift 2 ;;
		--roots) ROOTS="$2"; shift 2 ;;
		*) echo "Unknown arg: $1" >&2; exit 2 ;;
	esac
done

SRC=""
IFS=':' read -r -a ROOT_ARR <<<"$ROOTS"
for r in "${ROOT_ARR[@]}"; do
	if [ -f "$r/$ID/manifest.md" ]; then SRC="$r/$ID"; break; fi
done
[ -n "$SRC" ] || { echo "Unknown addon: $ID (searched: $ROOTS)" >&2; exit 1; }

VERSION="$(awk '/^---[[:space:]]*$/{fm++;next} fm==1 && /^version:/{sub(/^version:[[:space:]]*/,""); sub(/[[:space:]]*#.*$/,""); print; exit}' "$SRC/manifest.md")"
[ -n "$VERSION" ] || { echo "ERROR: $SRC/manifest.md has no version: field" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/$ID"
rsync -a "$SRC/" "$TMP/$ID/" \
	--exclude 'enabled' --exclude '*.log' --exclude 'state.*' --exclude 'stats.*' \
	--exclude '*.lock' --exclude '*.cache' --exclude '.DS_Store' \
	--exclude 'node_modules' --exclude '*.backup.*'

# Carry the repository license into the standalone addon package so distributed
# addons are not rights-ambiguous (the repo is Apache-2.0 licensed).
cp "$ROOT/LICENSE" "$TMP/$ID/LICENSE"

# Privacy gate: a packaged addon is a publishable artefact.
bash "$ROOT/scripts/privacy-scan.sh" --dir "$TMP/$ID"

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/addon-$ID-v$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
(cd "$TMP" && zip -r -y -q "$ZIP" "$ID")
(
	cd "$OUT_DIR"
	base="$(basename "$ZIP")"
	# Portable: shasum (macOS) or sha256sum (Linux). Both emit `<hash>  <file>`
	# so the .sha256 sidecar stays `shasum -c`/`sha256sum -c` compatible.
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$base"
	else sha256sum "$base"; fi > "$base.sha256"
)
echo "Packaged: $ZIP"
cat "$ZIP.sha256"
