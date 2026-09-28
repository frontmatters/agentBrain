#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# vault-post-commit.sh — auto-push the vault after each commit, versioned SOURCE.
# Installed by scripts/sync/sync-vault.sh next to vault-pre-commit.sh.
#
# post-commit (local/ repo) — auto-push to gitea origin.
#
# Runs git push in the background after each successful commit. Failures are
# silent (commits still happen locally even if push can't reach gitea), but
# logged to /tmp/agentbrain-local-push.log for diagnosis.
#
# Skip-escape (two ways): env COMMIT_SKIP_PUSH=1 git commit ...  OR put a
# [skip-push] (also [no-push] / [local-only]) marker in the commit message —
# self-documenting and decided at commit time, ideal for local-only work you
# want to review before pushing.

commit_msg="$(git log -1 --pretty=%B 2>/dev/null || true)"
if [[ "${COMMIT_SKIP_PUSH:-0}" = "1" ]] \
  || printf '%s' "$commit_msg" | grep -qiE '\[(skip[ _-]?push|no[ _-]?push|local[ _-]?only)\]'; then
  echo "post-commit: skip-push requested (env or [skip-push] marker) — auto-push skipped" >&2
  exit 0
fi

# Skip during rebase / cherry-pick / revert — non-fast-forward is guaranteed and
# per-commit force-push is dangerous. Catch-up happens with a single push after
# the rebase finishes.
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [ -n "$git_dir" ] && { [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ] || [ -d "$git_dir/sequencer" ]; }; then
  echo "post-commit: rebase/cherry-pick in progress — skipping auto-push" >&2
  exit 0
fi

# Background push so the user's terminal doesn't block on network. Log for diagnosis.
(
  log="/tmp/agentbrain-local-push.log"
  if git push origin HEAD >>"$log" 2>&1; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] push OK: $(git rev-parse --short HEAD)" >> "$log"
  else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] push FAILED for $(git rev-parse --short HEAD) — see lines above" >> "$log"
  fi
) &
disown $!

echo "post-commit: auto-push backgrounded (log: /tmp/agentbrain-local-push.log)" >&2
