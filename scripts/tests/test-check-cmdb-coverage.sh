#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHK="$ROOT_DIR/scripts/checks/check-cmdb-coverage.sh"
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:[$2] want:[$3])"; fails=$((fails+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/devices" "$TMP/integrations"
# A CI with relations (ok) and one with none (should be reported).
cat > "$TMP/devices/host-a.md" <<'EOF'
---
type: device
provides: [svc-a]
---
# host-a
EOF
cat > "$TMP/integrations/svc-a.md" <<'EOF'
---
type: integration
hosted_on: [host-a]
---
# svc-a
EOF
cat > "$TMP/integrations/orphan.md" <<'EOF'
---
type: integration
---
# orphan
EOF
# A relation-looking line in the BODY (not frontmatter) must NOT count as a relation —
# _has_relation is frontmatter-scoped to match brain-cmdb's _relfield (both tools agree).
cat > "$TMP/integrations/body-only.md" <<'EOF'
---
type: integration
---
# body-only

Example: hosted_on: some-host
EOF
# An opted-in project (has ci:) with no relations must be flagged; a non-ci project must not.
mkdir -p "$TMP/projects/orphan-proj"
cat > "$TMP/projects/orphan-proj/index.md" <<'EOF'
---
type: project
ci: ci-33333333
---
# orphan-proj
EOF
mkdir -p "$TMP/projects/idea-only"
cat > "$TMP/projects/idea-only/index.md" <<'EOF'
---
type: project
---
# idea-only
EOF

out="$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$CHK" 2>&1; echo "rc=$?")"
assert "always exits 0"          "$(printf '%s' "$out" | grep -c 'rc=0')" "1"
assert "flags CI without relations" "$(printf '%s' "$out" | grep -c 'orphan (no relations)')" "1"
assert "does not flag related CI"   "$(printf '%s' "$out" | grep -c 'svc-a (no relations)')" "0"
# body-only has no frontmatter relation → must be flagged as an orphan.
assert "body relation does not count" "$(printf '%s' "$out" | grep -c 'body-only (no relations)')" "1"
assert "flags opted-in project w/o relations" "$(printf '%s' "$out" | grep -c 'orphan-proj (no relations)')" "1"
assert "ignores non-ci project"               "$(printf '%s' "$out" | grep -c 'idea-only')" "0"

# --space scopes the audit to the space AND skips the personal-checkout remote-host
# heuristic (which is meaningless for a space audit).
mkdir -p "$TMP/spaces/client-a/integrations"
cat > "$TMP/spaces/client-a/integrations/client-svc.md" <<'EOF'
---
type: integration
ci: ci-44444444
---
# client-svc
EOF
sout="$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$CHK" --space client-a 2>&1; echo "rc=$?")"
assert "space audit exits 0"          "$(printf '%s' "$sout" | grep -c 'rc=0')" "1"
assert "space audit flags client CI"  "$(printf '%s' "$sout" | grep -c 'client-svc (no relations)')" "1"
assert "space audit ignores personal" "$(printf '%s' "$sout" | grep -c 'orphan-proj')" "0"
assert "space audit skips remote heuristic" "$(printf '%s' "$sout" | grep -c 'has no device note')" "0"

if [ "$fails" -eq 0 ]; then echo "test-check-cmdb-coverage: ok"; else echo "test-check-cmdb-coverage: $fails fail(s)" >&2; exit 1; fi
