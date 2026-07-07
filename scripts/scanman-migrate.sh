#!/usr/bin/env bash
# scanman-migrate.sh — repair pre-v0.0.3 scanman workspaces so they pass
# the agentBrain validate-hook + check-local-content checks.
#
# Two failure modes are fixed:
#   1. Missing YAML frontmatter entirely (early scanman scripts didn't add it
#      to 00/00b/01/02 — only init touched 03/04/05/index)
#   2. Mismatched id field (caused by directory renames after init; UUID5 is
#      derived from the path, so renaming breaks the hash)
#
# Idempotent: re-running on an already-clean workspace is a no-op.

set -uo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$AGENTBRAIN_DIR" || exit 2

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "DRY RUN: no files will be modified"
  echo ""
fi

artifact_for() {
  case "$1" in
    index.md)                 echo "index" ;;
    00-file-inventory.md)     echo "file-inventory" ;;
    00b-dependency-map.md)    echo "dependency-map" ;;
    01-system-map.md)         echo "system-map" ;;
    02-runtime-model.md)      echo "runtime-model" ;;
    03-core-primitives.md)    echo "core-primitives" ;;
    04-risk-and-bloat.md)     echo "risk-and-bloat" ;;
    05-redesign-v1.md)        echo "redesign-v1" ;;
    *)                        echo "${1%.md}" ;;
  esac
}

today=$(date +%F)
added=0
updated=0
skipped=0

for ws in local/research/repo-distill/*/; do
  slug=$(basename "$ws")
  for f in "$ws"*.md; do
    [[ -f "$f" ]] || continue
    filename=$(basename "$f")
    rel="${f#./}"
    rel_noext="${rel%.md}"
    expected=$(bash scripts/uuid5-gen.sh "$rel_noext")

    artifact=$(artifact_for "$filename")

    if ! head -1 "$f" | grep -q '^---'; then
      # No frontmatter — prepend a fresh block
      if [[ "$DRY_RUN" == true ]]; then
        echo "  WOULD ADD frontmatter: $rel (id=$expected)"
      else
        tmp=$(mktemp)
        {
          echo "---"
          echo "date: $today"
          echo "type: research"
          echo "tags: [repo-distill, architecture, analysis]"
          echo "status: active"
          echo "id: $expected"
          echo "repo: $slug"
          echo "artifact: $artifact"
          echo "source: session"
          echo "---"
          echo ""
          cat "$f"
        } > "$tmp"
        mv "$tmp" "$f"
      fi
      added=$((added + 1))
    else
      actual=$(grep -E '^id:' "$f" 2>/dev/null | sed 's/id: *//' | head -1 | tr -d ' ')
      if [[ -n "$actual" && "$expected" != "$actual" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          echo "  WOULD UPDATE id: $rel ($actual -> $expected)"
        else
          sed -i.bak "s/^id: .*/id: $expected/" "$f"
          rm -f "$f.bak"
        fi
        updated=$((updated + 1))
      else
        skipped=$((skipped + 1))
      fi
    fi
  done
done

echo ""
echo "Migration summary:"
echo "  Frontmatter added: $added"
echo "  Stale IDs corrected: $updated"
echo "  Already clean: $skipped"
echo "  Total touched: $((added + updated))"
