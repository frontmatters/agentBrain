#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../bin/brain-cmdb"
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:[$2] want:[$3])"; fails=$((fails+1)); fi; }

# Hermetic CI vault.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/devices" "$TMP/integrations"
cat > "$TMP/devices/gitea-host.md" <<'EOF'
---
id: 1
type: device
role: "LAN server"
provides: [ab-registry, gitea]
---
# gitea-host
EOF
cat > "$TMP/integrations/ab-registry.md" <<'EOF'
---
id: 2
type: integration
hosted_on: [gitea-host]
depends_on: [gitea]
---
# ab-registry
EOF
cat > "$TMP/integrations/gitea.md" <<'EOF'
---
id: 3
type: integration
hosted_on: [gitea-host]
---
# gitea
EOF
# A block-format (YAML `- item`) fixture — exercises _relfield's block branch.
cat > "$TMP/devices/host-b.md" <<'EOF'
---
id: 4
type: device
depends_on:
  - gitea
  - tailscale
---
# host-b
EOF

# A PROJECT that opted into the CMDB (carries a ci: id) — a software CI.
mkdir -p "$TMP/projects/checklister"
cat > "$TMP/projects/checklister/index.md" <<'EOF'
---
type: project
ci: ci-11111111
depends_on: [gitea]
hosted_on: [gn100]
---
# checklister
EOF
# A PROJECT with NO ci: field — must stay OUT of the graph.
mkdir -p "$TMP/projects/some-idea"
cat > "$TMP/projects/some-idea/index.md" <<'EOF'
---
type: project
---
# some-idea
EOF
# A SPACE with its own isolated CI (must never appear in the personal graph).
mkdir -p "$TMP/spaces/client-a/devices"
cat > "$TMP/spaces/client-a/devices/client-nas.md" <<'EOF'
---
type: device
ci: ci-22222222
---
# client-nas
EOF
export AGENTBRAIN_LOCAL_DIR="$TMP"

# list: every CI (devices + integrations), one slug per line, sorted.
assert "list" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" list | tr '\n' ' ' | sed 's/ *$//')" "ab-registry checklister gitea gitea-host host-b"
# _relfield via the hidden 'rel' debug command: read a YAML-list field (inline + block).
assert "rel provides" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel gitea-host provides)" "ab-registry gitea"
assert "rel hosted_on" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel ab-registry hosted_on)" "gitea-host"
assert "rel block depends_on" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel host-b depends_on)" "gitea tailscale"
assert "rel missing empty" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel gitea provides)" ""
# resolve: a slug -> its file path (devices first, then integrations).
assert "resolve device" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve gitea-host | sed "s#$TMP/##")" "devices/gitea-host.md"
assert "resolve integration" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve gitea | sed "s#$TMP/##")" "integrations/gitea.md"

# runs-on: CIs whose hosted_on includes the host.
assert "runs-on" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" runs-on gitea-host | tr '\n' ' ' | sed 's/ *$//')" "ab-registry gitea"
# what-depends-on: reverse deps (CIs whose depends_on includes the target).
assert "what-depends-on gitea" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" what-depends-on gitea | tr '\n' ' ' | sed 's/ *$//')" "ab-registry checklister host-b"
# show: prints the CI + its relation fields (grep-checked, order-independent).
show_out="$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" show ab-registry)"
assert "show names ci"      "$(printf '%s' "$show_out" | grep -c 'ab-registry')" "1"
assert "show hosted_on"     "$(printf '%s' "$show_out" | grep -c 'hosted_on: gitea-host')" "1"
assert "show depends_on"    "$(printf '%s' "$show_out" | grep -c 'depends_on: gitea')" "1"
# ab-registry has no `provides` — _show must suppress empty fields (tests the || true fix).
assert "show suppresses empty" "$(printf '%s' "$show_out" | grep -c 'provides')" "0"
# unknown CI -> exit 1 (the || continue in the test avoids aborting under set -e).
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" show no-such-ci >/dev/null 2>&1 && ec=0 || ec=$?
assert "show unknown exit 1" "$ec" "1"

AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" sync >/dev/null
synced="$(cat "$TMP/integrations/ab-registry.md")"
assert "sync adds relations header"  "$(printf '%s' "$synced" | grep -c '^## Relations')" "1"
assert "sync adds hosted_on link"    "$(printf '%s' "$synced" | grep -c 'hosted_on:: \[\[gitea-host\]\]')" "1"
assert "sync adds depends_on link"   "$(printf '%s' "$synced" | grep -c 'depends_on:: \[\[gitea\]\]')" "1"
# Idempotent: a second sync must not duplicate the section.
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" sync >/dev/null
assert "sync idempotent" "$(grep -c '^## Relations' "$TMP/integrations/ab-registry.md")" "1"
# gitea-host has `provides`, so it also gets exactly one section.
assert "provides-only gets section" "$(grep -c '^## Relations' "$TMP/devices/gitea-host.md")" "1"

# Stale-block removal (data safety): strip all relations from a CI's frontmatter,
# re-sync — the generated block AND its heading must be gone, not left dangling.
cat > "$TMP/integrations/ab-registry.md" <<'EOF'
---
id: 2
type: integration
---
# ab-registry
EOF
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" sync >/dev/null
assert "sync removes stale markers" "$(grep -c 'cmdb:relations' "$TMP/integrations/ab-registry.md")" "0"
assert "sync removes stale heading" "$(grep -c '^## Relations' "$TMP/integrations/ab-registry.md")" "0"
# ...and the hand-written body survives the strip.
assert "sync keeps note body"       "$(grep -c '^# ab-registry' "$TMP/integrations/ab-registry.md")" "1"

# A non-ci project is excluded from the graph.
assert "list excludes non-ci project" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" list | grep -c '^some-idea$')" "0"
# A project resolves to its folder/index.md.
assert "resolve project" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve checklister | sed "s#$TMP/##")" "projects/checklister/index.md"
# A project WITHOUT a ci: field is not a CI — it must not resolve (exit 1).
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve some-idea >/dev/null 2>&1 && ec=0 || ec=$?
assert "non-ci project does not resolve" "$ec" "1"
# Space isolation: --space scopes to the space, personal never sees client CIs.
assert "space scopes to client"   "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" --space client-a list | tr '\n' ' ' | sed 's/ *$//')" "client-nas"
assert "personal excludes client" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" list | grep -c 'client-nas')" "0"

# register mints a ci- + 8-hex id, is idempotent, and marks a project as a CI.
mkdir -p "$TMP/projects/new-proj"
cat > "$TMP/projects/new-proj/index.md" <<'EOF'
---
type: project
depends_on: [gitea]
---
# new-proj
EOF
id1="$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" register new-proj)"
assert "register mints ci- id"    "$(printf '%s' "$id1" | grep -cE '^ci-[0-9a-f]{8}$')" "1"
id2="$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" register new-proj)"
assert "register idempotent"      "$id1" "$id2"
assert "registered project now a CI" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" list | grep -c '^new-proj$')" "1"
assert "register wrote frontmatter"  "$(grep -c '^ci: ci-' "$TMP/projects/new-proj/index.md")" "1"
# --backfill mints ci: for every device + integration lacking one (gitea-host/gitea/etc).
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" register --backfill >/dev/null
assert "backfill stamps a device"      "$(grep -c '^ci: ci-' "$TMP/devices/gitea-host.md")" "1"
assert "backfill stamps an integration" "$(grep -c '^ci: ci-' "$TMP/integrations/gitea.md")" "1"
# Backfill is idempotent — a second run keeps the same id on gitea-host.
before="$(awk '/^ci:/{print;exit}' "$TMP/devices/gitea-host.md")"
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" register --backfill >/dev/null
after="$(awk '/^ci:/{print;exit}' "$TMP/devices/gitea-host.md")"
assert "backfill idempotent" "$before" "$after"
# Data safety: register on a note with NO frontmatter must FAIL (exit 1), not falsely
# report a mint it never wrote, and must not leave a temp file behind.
mkdir -p "$TMP/projects/no-fm"
printf '# no-fm\n' > "$TMP/projects/no-fm/index.md"
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" register no-fm >/dev/null 2>&1 && ec=0 || ec=$?
assert "register no-frontmatter fails" "$ec" "1"
assert "register no-frontmatter no ci" "$(grep -c '^ci:' "$TMP/projects/no-fm/index.md")" "0"
assert "register no-frontmatter no temp" "$(find "$TMP/projects/no-fm" -name 'index.md.*' | wc -l | tr -d ' ')" "0"

# resolve a ci-id back to its slug (reverse lookup).
assert "resolve ci-id -> slug" "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve ci-11111111)" "checklister"
# resolve an unknown ci-id -> error exit 1.
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve ci-deadbeef >/dev/null 2>&1 && ec=0 || ec=$?
assert "resolve unknown ci-id exit 1" "$ec" "1"

# rename: dedicated ISOLATED fixtures (the shared fixtures were mutated by earlier
# tests — sync stripped ab-registry, backfill stamped others). Covers inline + block
# referrers and a whole-slug decoy (svc-x-tra must NOT be rewritten by svc-x->svc-y).
cat > "$TMP/integrations/svc-x.md" <<'EOF'
---
type: integration
ci: ci-aaaaaaaa
---
# svc-x
EOF
cat > "$TMP/integrations/app-inline.md" <<'EOF'
---
type: integration
depends_on: [svc-x, keep]
---
# app-inline
EOF
cat > "$TMP/devices/box.md" <<'EOF'
---
type: device
depends_on:
  - svc-x
  - svc-x-tra
---
# box
EOF
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rename svc-x svc-y >/dev/null
assert "rename moved the note"     "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve svc-y | sed "s#$TMP/##")" "integrations/svc-y.md"
assert "rename rewrote inline ref"  "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel app-inline depends_on)" "svc-y keep"
assert "rename rewrote block ref"   "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rel box depends_on)" "svc-y svc-x-tra"
assert "whole-slug decoy intact"    "$(grep -c 'svc-x-tra' "$TMP/devices/box.md")" "1"
assert "old slug gone from graph"   "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" what-depends-on svc-x | tr '\n' ' ' | sed 's/ *$//')" ""
# ci: id is preserved across the rename (surrogate key is immutable).
assert "rename preserves ci: id"    "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve ci-aaaaaaaa)" "svc-y"
# Collision safety: renaming a project CI onto an existing NON-CI project folder must
# refuse (mv would otherwise nest old inside new) and leave the source in place.
mkdir -p "$TMP/projects/proj-a" "$TMP/projects/proj-b"
cat > "$TMP/projects/proj-a/index.md" <<'EOF'
---
type: project
ci: ci-bbbbbbbb
---
# proj-a
EOF
cat > "$TMP/projects/proj-b/index.md" <<'EOF'
---
type: project
---
# proj-b
EOF
AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" rename proj-a proj-b >/dev/null 2>&1 && ec=0 || ec=$?
assert "rename refuses non-ci collision" "$ec" "1"
assert "collision left source in place"  "$(AGENTBRAIN_LOCAL_DIR="$TMP" bash "$BIN" resolve proj-a | sed "s#$TMP/##")" "projects/proj-a/index.md"

if [ "$fails" -eq 0 ]; then echo "test-brain-cmdb: ok"; else echo "test-brain-cmdb: $fails fail(s)" >&2; exit 1; fi
