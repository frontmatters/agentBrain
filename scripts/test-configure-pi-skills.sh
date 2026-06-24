#!/usr/bin/env bash
# shellcheck disable=SC2015,SC1091
# - SC2015 `[ X ] && ok || ko`: intentional one-liner asserts; `ok` always
#   succeeds, so the `|| ko` branch only runs on the assert-failure path.
# - SC1091: sources configure-pi.sh via a dynamic path; it's checked on its own.
# Hermetic test for configure-pi.sh addon-skill linking: an ENABLED addon that
# ships a SKILL.md is linked into Pi's skills dir, and pruned once disabled.
# Sources configure-pi.sh (main-guarded) and drives link_addon_skills against a
# throwaway brain + Pi config dir, so it never touches the real ~/.pi.
# Usage: bash scripts/test-configure-pi-skills.sh ; exit 0 pass, 1 fail.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Temp brain: an addon that ships a SKILL.md, plus its enabled-state dir.
mkdir -p "$TEST_DIR/brain/system/addons/graphify" "$TEST_DIR/brain/local/addons/graphify"
cat > "$TEST_DIR/brain/system/addons/graphify/SKILL.md" <<'EOF'
---
name: graphify
description: fixture
user-invocable: true
---
# Graphify
EOF

# Point configure-pi.sh at the temp brain + a throwaway Pi config dir. BRAIN_ALIAS
# must exist so PI_SRC resolves to the temp brain (not the real ~/agentBrain).
export AGENTBRAIN_HOME="$TEST_DIR/home"
export AGENTBRAIN_DIR="$TEST_DIR/brain"
export BRAIN_ALIAS="$TEST_DIR/brain"
export PI_CONFIG_DIR="$TEST_DIR/pi"
export PI_CONFIG_SOURCE="$TEST_DIR/brain/system/pi-config"
export ADDONS_STATE="$TEST_DIR/brain/local/addons"

# Load helpers without running the installer (main-guard).
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/configure-pi.sh"
set +eo pipefail

pass=0; fail=0
ok() { pass=$((pass + 1)); }
ko() { fail=$((fail + 1)); echo "  ✗ FAIL: $1" >&2; }

SKILL="$PI_CONFIG_DIR/skills/graphify/SKILL.md"

# enabled -> linked
: > "$TEST_DIR/brain/local/addons/graphify/enabled"
link_addon_skills
[ -L "$SKILL" ] && ok || ko "enabled addon skill not linked into Pi"
[ "$(readlink "$SKILL" 2>/dev/null | grep -c 'system/addons/graphify/SKILL.md')" = "1" ] && ok || ko "Pi skill link target wrong"

# disabled -> pruned on next sync
rm -f "$TEST_DIR/brain/local/addons/graphify/enabled"
link_addon_skills
{ [ -e "$SKILL" ] && ko "disabled addon skill still linked in Pi"; } || ok

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
