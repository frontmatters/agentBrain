#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../bin/brain-ops"
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:[$2] want:[$3])"; fails=$((fails+1)); fi; }
contains() { case "$2" in *"$3"*) echo "ok   $1" ;; *) echo "FAIL $1 (got:[$2] missing:[$3])"; fails=$((fails+1)) ;; esac; }

# Hermetic ops vault. AGENTBRAIN_LOCAL_DIR set → no context.sh, and brain-cmdb resolve
# (soft dep) finds no CIs here, so `on`/`timeline` fall back to raw-token matching.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export AGENTBRAIN_LOCAL_DIR="$TMP"
mkdir -p "$TMP/ops/incidents" "$TMP/ops/problems" "$TMP/ops/known-errors" "$TMP/ops/postmortems"

cat > "$TMP/ops/incidents/2026-08-16-gitea-reboot-lockout.md" <<'EOF'
---
id: 1
type: incident
status: resolved
occurred: 2026-08-16
ci: [ci-9f3e2a1b]
problem: ssh-boot-order
---
# gitea reboot lockout
EOF
cat > "$TMP/ops/incidents/2026-08-17-disk-full.md" <<'EOF'
---
id: 2
type: incident
status: open
occurred: 2026-08-17
ci: [ci-9f3e2a1b, ci-deadbeef]
---
# disk full
EOF
cat > "$TMP/ops/problems/ssh-boot-order.md" <<'EOF'
---
id: 3
type: problem
status: known
ci: [ci-9f3e2a1b]
incidents: [2026-08-16-gitea-reboot-lockout]
known_error: ssh-listenaddress-preboot
---
# ssh boot-order dependency
EOF
cat > "$TMP/ops/known-errors/ssh-listenaddress-preboot.md" <<'EOF'
---
id: 4
type: known-error
status: active
ci: [ci-9f3e2a1b]
problem: ssh-boot-order
---
# ListenAddress before tailscale0 exists
EOF
cat > "$TMP/ops/postmortems/2026-08-16-gitea-reboot.md" <<'EOF'
---
id: 5
type: postmortem
date: 2026-08-16
incident: 2026-08-16-gitea-reboot-lockout
ci: [ci-9f3e2a1b]
---
# postmortem
EOF

# on <ci> — every record touching the CI (4 records reference ci-9f3e2a1b)
OUT="$("$BIN" on ci-9f3e2a1b)"
assert "on: record count" "$(printf '%s\n' "$OUT" | grep -c .)" "5"
contains "on: incident present" "$OUT" "gitea-reboot-lockout"
contains "on: known-error present" "$OUT" "ssh-listenaddress-preboot"

# on <ci> — the second CI only touches one incident
assert "on: other CI single" "$("$BIN" on ci-deadbeef | grep -c .)" "1"

# incidents --open — only the open one
OUT="$("$BIN" incidents --open)"
assert "incidents --open: count" "$(printf '%s\n' "$OUT" | grep -c .)" "1"
contains "incidents --open: disk-full" "$OUT" "disk-full"

# incidents (all) — both
assert "incidents: all" "$("$BIN" incidents | grep -c .)" "2"

# known-errors --ci
assert "known-errors --ci" "$("$BIN" known-errors --ci ci-9f3e2a1b | grep -c .)" "1"

# problems
contains "problems" "$("$BIN" problems)" "ssh-boot-order"

# timeline <ci> — incidents + postmortems, chronological
OUT="$("$BIN" timeline ci-9f3e2a1b)"
assert "timeline: incidents+postmortems count" "$(printf '%s\n' "$OUT" | grep -c .)" "3"

# show <slug> — record + its links
OUT="$("$BIN" show ssh-boot-order)"
contains "show: type" "$OUT" "type: problem"
contains "show: known_error link" "$OUT" "ssh-listenaddress-preboot"

# unknown slug fails
"$BIN" show does-not-exist 2>/dev/null && { echo "FAIL show: should fail on unknown"; fails=$((fails+1)); } || echo "ok   show: unknown fails"

echo "---"
[ "$fails" -eq 0 ] && echo "all brain-ops tests passed" || { echo "$fails test(s) failed"; exit 1; }
