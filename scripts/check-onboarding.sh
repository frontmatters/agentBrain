#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-onboarding.sh — report whether personal onboarding is complete.
# "Complete" = no personal preference file still carries a template placeholder
# marker (the same markers /config preferences and /onboard treat as "needs
# onboarding"). Exit 0 = complete, exit 1 = incomplete — so doctor and setup can
# surface the drift (gap G2 seam / E2 completeness signal).
set -euo pipefail
VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
PREFS="$VAULT/local/preferences/personal"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Canonical "not onboarded yet" markers (see system/skills/config/SKILL.md).
markers='This is an example|^<!-- Example:'

incomplete=()
if [ -d "$PREFS" ]; then
  while IFS= read -r f; do
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue
    if grep -qE "$markers" "$f"; then incomplete+=("$base"); fi
  done < <(find "$PREFS" -maxdepth 1 -name '*.md' -type f | sort)
fi

if [ ! -d "$PREFS" ] || [ "${#incomplete[@]}" -gt 0 ]; then
  # During INITIAL setup this state is expected, not a failure: show it as the
  # next step (exit 0) so a perfect install never ends with a red X. Standalone
  # doctor runs (later sessions) still fail — the drift signal stays (G2/E2).
  if [ "${AGENTBRAIN_SETUP_PHASE:-}" = "1" ] || [ "${AGENTBRAIN_ONBOARDING_PENDING_OK:-}" = "1" ]; then
    echo -e "${YELLOW}⏳ Onboarding pending${NC} — final step: run /onboard inside your agent."
    exit 0
  fi
  echo -e "${YELLOW}Onboarding incomplete${NC} — run /onboard to personalize:"
  if [ ! -d "$PREFS" ]; then
    echo "  local/preferences/personal/ missing"
  else
    for b in "${incomplete[@]}"; do echo "  - $b (still a template)"; done
  fi
  exit 1
fi
echo -e "${GREEN}Onboarding complete${NC} — personal preferences personalized."
exit 0
