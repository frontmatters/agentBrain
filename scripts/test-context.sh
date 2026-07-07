#!/usr/bin/env bash
# test-context.sh — unit tests for system/lib/context.sh infer_context().
# One case per row of the spaces-context-model "breukgevallen" table, on a
# self-contained fixture (no real client dirs needed → machine-independent).
#
# NB: fixture slugs are deliberately NEUTRAL (alpha/beta) — never real space
# slugs or owner names — so this public script cannot leak a client identity
# (see scripts/check-space-boundary.sh).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-context-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/system/lib" \
         "$FIXTURE/local/spaces/alpha/learnings" \
         "$FIXTURE/local/spaces/beta" \
         "$FIXTURE/local/learnings"
cp "$ROOT_DIR/system/lib/context.sh" "$FIXTURE/system/lib/"

# Fake code-root dirs + a reverse-map that points at them.
CR_A="$FIXTURE/code/alpha-app"; CR_B="$FIXTURE/code/beta-app"
mkdir -p "$CR_A" "$CR_B/src/deep"
cat > "$FIXTURE/local/.space-map.json" <<EOF
{
  "by-alias": { "alpha": "alpha", "alp": "alpha", "beta": "beta" },
  "by-code-root": { "$CR_A": "alpha", "$CR_B": "beta" }
}
EOF
printf -- '---\ntype: space\nslug: alpha\n---\n' > "$FIXTURE/local/spaces/alpha/index.md"
printf -- '---\ntype: space\nslug: beta\n---\n'  > "$FIXTURE/local/spaces/beta/index.md"

CTX="$FIXTURE/system/lib/context.sh"

PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }
expect(){ # desc want got
	if [ "$3" = "$2" ]; then ok "$1 (=$3)"; else no "$1: got '$3' want '$2'"; fi
}

# 6) explicit env override wins, resolving aliases.
expect "env AGENTBRAIN_CONTEXT wins" alpha \
	"$(AGENTBRAIN_CONTEXT=alpha bash -c 'source "$1"; infer_context' _ "$CTX")"
expect "env alias alp → alpha" alpha \
	"$(AGENTBRAIN_CONTEXT=alp bash -c 'source "$1"; infer_context' _ "$CTX")"

# 1) file in a space-subtree → that space (path).
expect "file under spaces/alpha" alpha \
	"$(bash -c 'source "$1"; infer_context "$2"' _ "$CTX" "$FIXTURE/local/spaces/alpha/learnings/x.md")"

# 2) frontmatter space: on a file outside any space dir.
FM="$FIXTURE/local/learnings/fm.md"; printf -- '---\nspace: beta\n---\n' > "$FM"
expect "frontmatter space: beta" beta \
	"$(bash -c 'source "$1"; infer_context "$2"' _ "$CTX" "$FM")"

# misfiled note: path=alpha but frontmatter=beta → ambiguous (refuse, don't guess).
MIS="$FIXTURE/local/spaces/alpha/learnings/mis.md"; printf -- '---\nspace: beta\n---\n' > "$MIS"
expect "path≠frontmatter → ambiguous" ambiguous \
	"$(bash -c 'source "$1"; infer_context "$2"' _ "$CTX" "$MIS")"

# 5) cwd under a code-root → that space; nested subdir uses longest-prefix.
expect "cwd under alpha code-root" alpha \
	"$(cd "$CR_A" && bash -c 'source "$1"; infer_context' _ "$CTX")"
expect "cwd nested under beta code-root" beta \
	"$(cd "$CR_B/src/deep" && bash -c 'source "$1"; infer_context' _ "$CTX")"

# breukgeval: `cd` elsewhere must NOT switch context — file path dominates cwd.
expect "file path dominates cwd" beta \
	"$(cd "$CR_A" && bash -c 'source "$1"; infer_context "$2"' _ "$CTX" "$FIXTURE/local/spaces/beta/y.md")"

# breukgeval: nothing known → unknown (caller decides personal/ask/refuse).
expect "no signal → unknown" unknown \
	"$(cd "$FIXTURE" && bash -c 'source "$1"; infer_context' _ "$CTX")"

# stale/absent map degrades gracefully: cwd-under-code-root drops out → unknown.
rm -f "$FIXTURE/local/.space-map.json"
expect "absent map → cwd signal drops out → unknown" unknown \
	"$(cd "$CR_A" && bash -c 'source "$1"; infer_context' _ "$CTX")"

echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "test-context: $FAIL failed, $PASS passed"
	exit 1
fi
echo "test-context: ✅ $PASS tests passed"
