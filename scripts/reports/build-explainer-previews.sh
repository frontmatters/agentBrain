#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate a preview.png thumbnail next to every rendered explainer (vault + spaces),
# via a screenshot command. Co-located: <explainer-dir>/preview.png — the
# explainer-index shows these as a visual gallery. Run after (re)rendering explainers.
#
# AGENTBRAIN_SCREENSHOT_CMD names the command to use; it is called as
# `<cmd> <url> <output.png>` and should capture the top 1000x720 of the page.
# Unset, the Playwright CLI is used when it is on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT/scripts/lib/vault.sh"
PORT="${1:-8794}"
SHOT_CMD="${AGENTBRAIN_SCREENSHOT_CMD:-}"
command -v "${SHOT_CMD:-playwright}" >/dev/null 2>&1 || { echo "${SHOT_CMD:-playwright} not found (set AGENTBRAIN_SCREENSHOT_CMD)"; exit 1; }

# One thumbnail: the top region only, fullpage is huge.
capture() {
	if [ -n "$SHOT_CMD" ]; then
		"$SHOT_CMD" "$1" "$2"
	else
		playwright screenshot --viewport-size "1000,720" "$1" "$2"
	fi
}

cd "$VAULT_DIR"
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT
sleep 1

n=0; skip=0
while IFS= read -r md; do
	grep -q '^type: explainer' "$md" 2>/dev/null || continue
	html="${md%.md}.html"
	[ -f "$html" ] || { skip=$((skip+1)); continue; }
	out="$VAULT_DIR/$(dirname "$md")/preview.png"
	if capture "http://127.0.0.1:${PORT}/${html}" "$out" >/dev/null 2>&1; then
		n=$((n+1))
	else
		skip=$((skip+1))
	fi
done < <(find explainers spaces -name '*.md' 2>/dev/null | sort)

echo "explainer-previews: ${n} generated, ${skip} skipped (no rendered html)"
