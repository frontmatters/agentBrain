#!/usr/bin/env bash
# agentBrain vault pre-commit gate.
#
# Blocks committing a note whose `id:` doesn't match uuid5-gen.sh for its path.
# Agent- and tool-agnostic by construction: it fires at git's commit boundary,
# for ANY committer (sync script, manual `git commit`, Claude Code, Pi, or a
# Bash heredoc that slipped past the per-agent Write/Edit hooks).
#
# This file is the versioned SOURCE. It is installed into
#   <vault>/.git/hooks/pre-commit
# by scripts/sync-agentbrain-local.sh (idempotent self-heal). It resolves the
# active checkout via the ~/agentBrain alias, so it survives `brain use dev|live`.
#
# --no-verify note: Pi's git-interceptor blocks `--no-verify`; the sync-script
# runs the same gate directly as a second line of defence for other paths.

set -euo pipefail

BRAIN="${AGENTBRAIN_DIR:-$HOME/agentBrain}"
GATE="$BRAIN/scripts/validate-staged-note-ids.sh"

# Missing checkout/gate → don't block on infrastructure; the sync-script gate and
# the doctor sweep remain as backstops.
[ -x "$GATE" ] || exit 0

exec bash "$GATE"
