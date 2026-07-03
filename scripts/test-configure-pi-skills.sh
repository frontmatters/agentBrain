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

# --- Fix #2: standalone skills (system/skills + local/skills) all link into Pi ---
mkdir -p "$TEST_DIR/brain/system/skills/doctor" "$TEST_DIR/brain/local/skills/myskill"
printf -- '---\nname: doctor\ndescription: fixture\n---\n# Doctor\n' > "$TEST_DIR/brain/system/skills/doctor/SKILL.md"
printf -- '---\nname: myskill\ndescription: fixture\n---\n# My\n' > "$TEST_DIR/brain/local/skills/myskill/SKILL.md"
skilllib_link_standalone_skills "$PI_CONFIG_DIR/skills" "$TEST_DIR/brain/system/skills" "system/skills" "$TEST_DIR/brain"
skilllib_link_standalone_skills "$PI_CONFIG_DIR/skills" "$TEST_DIR/brain/local/skills" "local/skills" "$TEST_DIR/brain"
[ -L "$PI_CONFIG_DIR/skills/doctor" ] && ok || ko "system skill not linked into Pi (Fix #2)"
[ -L "$PI_CONFIG_DIR/skills/myskill" ] && ok || ko "local skill not linked into Pi (Fix #2)"
# a user's own non-brain skill of the same name is left untouched
rm -f "$PI_CONFIG_DIR/skills/doctor"; : > "$PI_CONFIG_DIR/skills/userskill"
skilllib_link_standalone_skills "$PI_CONFIG_DIR/skills" "$TEST_DIR/brain/system/skills" "system/skills" "$TEST_DIR/brain"
[ -L "$PI_CONFIG_DIR/skills/doctor" ] && ok || ko "re-link of system skill failed"
# prune: removed source -> link gone; still-present source -> kept
rm -rf "$TEST_DIR/brain/system/skills/doctor"
skilllib_prune_orphaned_skills "$PI_CONFIG_DIR/skills" "$TEST_DIR/brain"
{ [ -e "$PI_CONFIG_DIR/skills/doctor" ] && ko "orphaned standalone skill not pruned (Fix #2)"; } || ok
[ -L "$PI_CONFIG_DIR/skills/myskill" ] && ok || ko "prune removed a still-present skill (Fix #2)"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
