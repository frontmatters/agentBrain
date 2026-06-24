#!/usr/bin/env bash
# loop-tick.sh — one tick of the self-improving loop: capture findings from all
# registered detectors, then refresh the startup-context surface.
#
# This is what the launchd agent (dev.agentbrain.loop) invokes on schedule.
# Also runnable by hand for ad-hoc refresh.
#
# Add a detector here once it supports --json output (see capture-findings.sh
# for the wire-up requirement). A failing detector logs + continues; one broken
# checker should not silence the rest of the loop.

set -uo pipefail   # not -e: we want to continue past individual detector failures
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DETECTORS=(
	"check-local-content"
)

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

echo "loop-tick: starting at $(ts)"

for det in "${DETECTORS[@]}"; do
	echo "loop-tick: capturing $det..."
	if ! bash "$SCRIPT_DIR/capture-findings.sh" "$det"; then
		echo "loop-tick: detector $det failed; continuing with the rest" >&2
	fi
done

echo "loop-tick: rendering findings-triage backlog..."
bash "$SCRIPT_DIR/render-findings-backlog.sh" || echo "loop-tick: render-findings-backlog failed" >&2

echo "loop-tick: refreshing startup-context..."
bash "$SCRIPT_DIR/update-startup-context.sh" || echo "loop-tick: update-startup-context failed" >&2

echo "loop-tick: done at $(ts)"
