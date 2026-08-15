#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-onboard-identity.sh — validate the identity seed template + its /onboard wiring.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT_DIR/user-preferences/identity.md"
SETUP="$ROOT_DIR/scripts/setup-templates.sh"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# 1) template exists and opens with YAML frontmatter
if [ -f "$TPL" ] && [ "$(head -n1 "$TPL")" = "---" ]; then pass "identity.md exists with frontmatter"; else fail "identity.md missing/no frontmatter"; fi
# 2) correct type + uuid5 placeholder (so setup-templates renders it)
if grep -q '^type: user-preference' "$TPL" && grep -q '^id: {{uuid5}}' "$TPL"; then pass "type + {{uuid5}} placeholder present"; else fail "type/{{uuid5}} missing"; fi
# 3) carries the canonical "not onboarded yet" marker (so check-onboarding detects it)
if grep -q 'This is an example' "$TPL"; then pass "carries onboarding marker"; else fail "no 'This is an example' marker"; fi
# 4) has the identity sections
if grep -qi '^## Name' "$TPL" && grep -qi '^## Email' "$TPL" && grep -qi '^## Git' "$TPL"; then pass "has Name/Email/Git sections"; else fail "missing identity sections"; fi
# 5) setup-templates.sh auto-seeds it via the user-preferences glob
if grep -q 'user-preferences"/\*.md' "$SETUP"; then pass "setup-templates globs user-preferences (auto-seed)"; else fail "no user-preferences glob in setup-templates"; fi

# 6) doctor runs the identity test
if grep -q 'test-onboard-identity.sh' "$ROOT_DIR/scripts/doctor.sh"; then
  pass "doctor runs onboard-identity test"; else fail "doctor does not run onboard-identity test"; fi

# 7) SKILL.md wires the identity step + argument-hint
SKILL="$ROOT_DIR/system/skills/onboard/SKILL.md"
if grep -qE '^6\. .identity\.md.' "$SKILL"; then pass "SKILL.md has the identity step"; else fail "SKILL.md missing identity step"; fi
if grep -q 'argument-hint:.*"identity"' "$SKILL"; then pass "argument-hint lists identity"; else fail "argument-hint missing identity"; fi

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
