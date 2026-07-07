#!/usr/bin/env bash
# validate-staged-note-ids.sh — commit-time note-id gate.
#
# Layer 3 of the agent-discipline enforcement framework: the ONLY truly
# agent-agnostic AND tool-agnostic layer. It runs at git's commit boundary, so
# it does not matter which agent (Claude Code, Pi, a future one) or which tool
# (Write/Edit, or a Bash `cat > x.md` heredoc that bypasses the per-agent Write
# hooks) produced the note — a note whose `id:` does not match uuid5-gen.sh for
# its path cannot be committed.
#
# Runs INSIDE the vault git repo (cwd = the vault working tree, whose paths are
# `learnings/x.md`, `projects/foo/index.md`, ...). The vault has no brain.json of
# its own, so each staged path is mapped to the checkout's `local/` view
# (`<checkout>/local/<rel>`) where validate-note-id.sh can walk up to brain.json.
#
# Invoked by:
#   - <vault>/.git/hooks/pre-commit (installed by sync-agentbrain-local.sh)
#   - sync-agentbrain-local.sh directly (belt-and-suspenders, pre-commit)
#
# Exit codes: 0 — all staged notes valid (or none). 1 — one or more mismatches.

set -euo pipefail

CHECKOUT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$CHECKOUT_ROOT/scripts/validate-note-id.sh"

[ -x "$VALIDATOR" ] || exit 0  # no validator (partial checkout) → don't block

fail=0
# Staged, added/copied/modified, markdown only. `mapfile` is bash-4 only (macOS
# ships bash 3.2), so use a while-read loop with process substitution.
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	view="$CHECKOUT_ROOT/local/$rel"      # vault-relative -> checkout local/ view
	[ -f "$view" ] || continue            # rename/delete target gone — skip
	if ! bash "$VALIDATOR" "$view"; then
		fail=1
	fi
done < <(git diff --cached --name-only --diff-filter=ACM -- '*.md' 2>/dev/null || true)

if [ "$fail" -ne 0 ]; then
	{
		echo ""
		echo "commit blocked: staged note(s) have an id that doesn't match uuid5-gen.sh."
		echo "Fix each id shown above, or rescaffold via scripts/new-note.sh, then re-commit."
	} >&2
	exit 1
fi
exit 0
