#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Remove git-email-guard from a target repo.
# Usage: bash uninstall.sh <repo-path>
set -euo pipefail

repo="${1:-.}"
hook_dst="$repo/.git/hooks/pre-commit"

if [[ -L "$hook_dst" ]] && readlink "$hook_dst" | grep -q "git-email-guard"; then
  rm "$hook_dst"
  echo "Removed: $hook_dst"
  # Restore backup if present
  latest_backup="$(ls -1 "${hook_dst}".bak.* 2>/dev/null | tail -1 || true)"
  if [[ -n "$latest_backup" ]]; then
    mv "$latest_backup" "$hook_dst"
    echo "Restored backup: $hook_dst"
  fi
else
  echo "No git-email-guard hook found at $hook_dst — nothing to do."
fi
