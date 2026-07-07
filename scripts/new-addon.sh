#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: bash scripts/new-addon.sh <id> <name>" >&2
  exit 1
fi

ADDON_ID="$1"
shift
ADDON_NAME="$*"
TARGET_DIR="$ROOT_DIR/system/addons/$ADDON_ID"
TEMPLATE_DIR="$ROOT_DIR/system/addons/_template"

if [[ ! "$ADDON_ID" =~ ^[a-z0-9-]+$ ]]; then
  echo "Addon id must be lowercase kebab-case: $ADDON_ID" >&2
  exit 1
fi

if [[ -e "$TARGET_DIR" ]]; then
  echo "Addon already exists: $TARGET_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$TEMPLATE_DIR/manifest.md" "$TARGET_DIR/manifest.md"
cp "$TEMPLATE_DIR/README.md" "$TARGET_DIR/README.md"

ADDON_ID="$ADDON_ID" ADDON_NAME="$ADDON_NAME" TARGET_DIR="$TARGET_DIR" python3 - <<'PY'
from pathlib import Path
import os
addon_id = os.environ["ADDON_ID"]
addon_name = os.environ["ADDON_NAME"]
target_dir = Path(os.environ["TARGET_DIR"])
for rel in ["manifest.md", "README.md"]:
    path = target_dir / rel
    text = path.read_text()
    text = text.replace("your-addon-id", addon_id)
    text = text.replace("Your Addon Name", addon_name)
    text = text.replace("your-command", addon_id)
    path.write_text(text)
PY

echo "Scaffolded addon: $TARGET_DIR"
echo "Next: edit manifest/README, then run:"
echo "  bash scripts/check-addons.sh $ADDON_ID"
echo "  bash scripts/privacy-scan.sh"
