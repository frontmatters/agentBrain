#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCANMAN_DIR="$AGENTBRAIN_DIR/system/skills/scanman"
VERSION_FILE="$SCANMAN_DIR/VERSION"
VERSION_DOC="$SCANMAN_DIR/VERSION.md"
CHANGELOG_FILE="$SCANMAN_DIR/CHANGELOG.md"

usage() {
  cat <<'EOF' >&2
Usage:
  bash scripts/scanman-bump-version.sh [patch] [--dry-run]
  bash scripts/scanman-bump-version.sh --show

Notes:
  - Scanman is intentionally locked to 0.0.x for now.
  - Bumping updates both VERSION and VERSION.md and seeds CHANGELOG if needed.
EOF
}

DRY_RUN=false
SHOW=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    patch) ;;  # patch is the only supported bump kind; accepted as a no-op for clarity
    --dry-run|-n) DRY_RUN=true ;;
    --show|--version|-v) SHOW=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ "$SHOW" == true ]]; then
  echo "$CURRENT"
  exit 0
fi

python3 - "$VERSION_FILE" "$VERSION_DOC" "$CHANGELOG_FILE" "$CURRENT" "$DRY_RUN" <<'PY'
from pathlib import Path
import datetime as dt
import re
import sys

version_file = Path(sys.argv[1])
version_doc = Path(sys.argv[2])
changelog = Path(sys.argv[3])
current = sys.argv[4]
dry_run = sys.argv[5].lower() == 'true'

m = re.fullmatch(r"0\.0\.(\d+)", current)
if not m:
    raise SystemExit(f"Scanman version must stay in 0.0.x for now, got: {current}")
new = f"0.0.{int(m.group(1)) + 1}"
print(f"Current version: {current}")
print(f"New version:     {new}")
if dry_run:
    print("Dry run: no files changed")
    raise SystemExit(0)

version_file.write_text(new + "\n")
text = version_doc.read_text()
text = re.sub(r"Current version: `[^`]+`", f"Current version: `{new}`", text, count=1)
version_doc.write_text(text)

date = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d")
heading = f"## {new} — {date}"
text = changelog.read_text()
if f"## {new}" not in text:
    block = f"{heading}\n- TODO: summarize scanman method changes\n\n"
    marker = "## "
    idx = text.find(marker)
    if idx != -1:
        text = text[:idx] + block + text[idx:]
    else:
        text = text.rstrip() + "\n\n" + block
    changelog.write_text(text)
PY
