#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-abh.sh — connect the optional agentBrain Harness to canonical agentBrain.
# ABH rc10 already ships the three providers in its base bundle. This script
# verifies that composition and only installs/mounts them for older ABH builds.
set -euo pipefail

if ! command -v abh >/dev/null 2>&1; then
  echo "agentBrain Harness not installed — skipped (install @agentbrain-harness/abh first)."
  exit 0
fi
[ "${AGENTBRAIN_SKIP_ABH:-}" = 1 ] && { echo "agentBrain Harness integration skipped (AGENTBRAIN_SKIP_ABH=1)."; exit 0; }

ABH_HOME_DIR="${ABH_HOME:-$HOME/.abh}"
PROFILE_DIR="$ABH_HOME_DIR/profiles/web"
PATCH="$PROFILE_DIR/cordis.patch.yml"
mkdir -p "$PROFILE_DIR"

cat <<'EOF'

agentBrain Harness integration
The agentBrain Harness is installed, so agentBrain will configure its Web profile automatically.
This enables:
  • agentBrain context: rules, preferences and project context
  • agentBrain memory: the local knowledge layer
  • agentBrain skills: system skills and enabled add-on skills
Only the agentBrain Harness Web profile changes. agentBrain remains the source of truth.
EOF

# Remove only the previous managed patch. ABH rc10's base bundle already mounts
# these providers; leaving our old rows would create duplicate loader IDs.
if [ -f "$PATCH" ] && grep -q '^# agentBrain integration, managed by scripts/setup/setup-abh.sh\.$' "$PATCH"; then
  printf '[]\n' > "$PATCH"
fi

config_dump="$(abh --profile web --dump-config 2>&1)" || {
  echo "agentBrain Harness profile could not be composed." >&2
  printf '%s\n' "$config_dump" >&2
  exit 1
}

if printf '%s\n' "$config_dump" | grep -q 'agentbrain-context' && \
   printf '%s\n' "$config_dump" | grep -q 'agentbrain-memory' && \
   printf '%s\n' "$config_dump" | grep -q 'skill-filesystem'; then
  echo "agentBrain Harness integration verified: base profile mounts context, memory and filesystem skill providers."
  exit 0
fi

# Older harness builds may not include the providers in base. Install the
# matching provider family, then mount a minimal, configured compatibility layer.
ABH_VERSION="$(abh --version 2>/dev/null | head -1 | tr -d '[:space:]')"
PACKAGE_SUFFIX=""
case "$ABH_VERSION" in 0.1.0-*) PACKAGE_SUFFIX="@$ABH_VERSION" ;; esac
abh plugin --profile web add \
  "@agentbrain-harness/agentbrain-context${PACKAGE_SUFFIX}" \
  "@agentbrain-harness/agentbrain-memory${PACKAGE_SUFFIX}" \
  "@agentbrain-harness/skill-filesystem${PACKAGE_SUFFIX}"

cat > "$PATCH" <<'YAML'
# agentBrain integration, managed by scripts/setup/setup-abh.sh.
- insert:
    - id: agentbrain-context-provider
      name: '@agentbrain-harness/agentbrain-context'
      config:
        maxBytes: 32768
        maxProjectBytes: 16384
    - id: agentbrain-memory-provider
      name: '@agentbrain-harness/agentbrain-memory'
    - id: agentbrain-skill-filesystem-provider
      name: '@agentbrain-harness/skill-filesystem'
      config:
        includeAgentBrainRoots: true
YAML

config_dump="$(abh --profile web --dump-config 2>&1)" || { printf '%s\n' "$config_dump" >&2; exit 1; }
for provider in agentbrain-context agentbrain-memory skill-filesystem; do
  printf '%s\n' "$config_dump" | grep -q "$provider" || { echo "agentBrain Harness profile verification failed: missing $provider" >&2; exit 1; }
done
echo "agentBrain Harness integration verified: compatibility providers are mounted."
