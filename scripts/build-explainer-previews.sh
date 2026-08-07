#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate a preview.png thumbnail next to every rendered explainer (vault + spaces),
# via snapcoder. Co-located: <explainer-dir>/preview.png — the explainer-index shows
# these as a visual gallery. Run after (re)rendering explainers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8794}"
command -v snapcoder >/dev/null 2>&1 || { echo "snapcoder not found"; exit 1; }

cd "$ROOT/local"
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1

n=0; skip=0
while IFS= read -r md; do
	grep -q '^type: explainer' "$md" 2>/dev/null || continue
	html="${md%.md}.html"
	[ -f "$html" ] || { skip=$((skip+1)); continue; }
	out="$ROOT/local/$(dirname "$md")/preview.png"
	# selection mode captures the top region as a thumbnail (visible mode has a
	# png/quality bug in this snapcoder build; fullpage is huge). 0,0,1000,720.
	if snapcoder capture "http://127.0.0.1:${PORT}/${html}" \
		--output "$out" --mode selection --selection "0,0,1000,720" \
		--width 1000 --height 800 >/dev/null 2>&1; then
		n=$((n+1))
	else
		skip=$((skip+1))
	fi
done < <(find explainers spaces -name '*.md' 2>/dev/null | sort)

echo "explainer-previews: ${n} generated, ${skip} skipped (no rendered html)"
