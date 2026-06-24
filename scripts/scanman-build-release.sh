#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCANMAN_DIR="$AGENTBRAIN_DIR/system/skills/scanman"
VERSION="$(tr -d '[:space:]' < "$SCANMAN_DIR/VERSION")"
OUT_DIR="${OUT_DIR:-$HOME/Developer/scanman/releases}"
RELEASE_NAME="scanman-v${VERSION}"
RELEASE_FILE="$OUT_DIR/${RELEASE_NAME}.zip"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$OUT_DIR"
BUNDLE_DIR="$TEMP_DIR/$RELEASE_NAME"
mkdir -p "$BUNDLE_DIR/system/skills/scanman" "$BUNDLE_DIR/templates" "$BUNDLE_DIR/scripts"

cp "$SCANMAN_DIR/SKILL.md" "$BUNDLE_DIR/system/skills/scanman/"
cp "$SCANMAN_DIR/VERSION" "$BUNDLE_DIR/system/skills/scanman/"
cp "$SCANMAN_DIR/VERSION.md" "$BUNDLE_DIR/system/skills/scanman/"
cp "$SCANMAN_DIR/CHANGELOG.md" "$BUNDLE_DIR/system/skills/scanman/"
cp "$SCANMAN_DIR/RELEASE.md" "$BUNDLE_DIR/system/skills/scanman/"
cp "$AGENTBRAIN_DIR"/templates/repo-distill-*.md "$BUNDLE_DIR/templates/"
cp "$AGENTBRAIN_DIR/scripts/scanman-"*.sh "$BUNDLE_DIR/scripts/"
chmod +x "$BUNDLE_DIR/scripts/"*.sh

cat > "$BUNDLE_DIR/README.md" <<EOF
# Scanman v$VERSION

Portable Scanman method bundle extracted from agentBrain.

Included:
- system/skills/scanman/
- templates/repo-distill-*.md
- scripts/scanman-*.sh
EOF

rm -f "$RELEASE_FILE"
(cd "$TEMP_DIR" && zip -r -q "$RELEASE_FILE" "$RELEASE_NAME")
echo "$RELEASE_FILE"
