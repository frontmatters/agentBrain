#!/usr/bin/env bash
# promote-to-shared.sh — move a local/ note (or folder) to shared/, regenerate its
# path-derived UUID5, log an old->new id map, and run the secret-gate.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
SHARED_DIR="${AGENTBRAIN_SHARED_DIR:-$ROOT_DIR/shared}"
GEN="${ROOT_DIR}/scripts/uuid5-gen.sh"
CHECK="${ROOT_DIR}/scripts/check-agentbrain-shared.sh"
REL="${1:?usage: promote-to-shared.sh <path-under-local-without-.md>}"
MAP="${SHARED_DIR}/.promote-id-map"

[ -d "$SHARED_DIR" ] || { echo "shared/ not set up (run setup-shared-vault.sh)" >&2; exit 1; }

promote_one() {
	local rel="$1"
	local src="$LOCAL_DIR/$rel.md" dst="$SHARED_DIR/$rel.md"
	[ -f "$src" ] || { echo "no such note: $src" >&2; return 1; }
	mkdir -p "$(dirname "$dst")"
	local oldid newid
	oldid="$(grep -m1 '^id:' "$src" | awk '{print $2}')"
	newid="$(bash "$GEN" "shared/$rel")"
	mv "$src" "$dst"
	perl -0pi -e "s/^id: .*\$/id: ${newid}/m" "$dst"
	printf '%s\t%s\t%s\n' "$rel" "$oldid" "$newid" >> "$MAP"
	echo "promoted: $rel  ($oldid -> $newid)"
}

if [ -d "$LOCAL_DIR/$REL" ]; then
	while IFS= read -r f; do
		local_rel="${f#"$LOCAL_DIR"/}"; local_rel="${local_rel%.md}"
		promote_one "$local_rel"
	done < <(find "$LOCAL_DIR/$REL" -name '*.md')
else
	promote_one "$REL"
fi

AGENTBRAIN_SHARED_DIR="$SHARED_DIR" bash "$CHECK" || { echo "Gate failed AFTER move — review $MAP to reverse." >&2; exit 1; }
echo "Done. Reverse via $MAP (move back + restore old id)."
