#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install git-email-guard pre-commit hook into a target repo.
# Usage: bash install.sh <repo-path> [email1 email2 ...]
#
# Examples:
#   bash install.sh ~/Developer/my-project you@example.com
#   bash install.sh .                    # uses existing .gitemail-allowed
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$ADDON_DIR/hooks/pre-commit"

repo="${1:-.}"
shift || true

if [[ ! -d "$repo/.git" ]]; then
  echo "Not a git repo: $repo" >&2
  exit 1
fi

repo="$(cd "$repo" && pwd)"
hook_dst="$repo/.git/hooks/pre-commit"

# Backup existing hook if it's not ours
if [[ -f "$hook_dst" ]] && ! grep -q "git-email-guard" "$hook_dst"; then
  backup="${hook_dst}.bak.$(date +%s)"
  mv "$hook_dst" "$backup"
  echo "Existing pre-commit moved to: $backup"
fi

# Use a symlink so addon updates propagate automatically
ln -sf "$HOOK_SRC" "$hook_dst"
chmod +x "$HOOK_SRC"
echo "Hook installed: $hook_dst → $HOOK_SRC"

# Seed whitelist if emails provided and file doesn't exist
whitelist="$repo/.gitemail-allowed"
if [[ $# -gt 0 ]] && [[ ! -f "$whitelist" ]]; then
  {
    echo "# git-email-guard: allowed author emails for this repo."
    echo "# One email per line. Lines starting with # are ignored."
    for email in "$@"; do echo "$email"; done
  } > "$whitelist"
  echo "Whitelist seeded: $whitelist"
elif [[ ! -f "$whitelist" ]]; then
  echo "Note: no .gitemail-allowed yet — create one or pass emails as install args."
fi
