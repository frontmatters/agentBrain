#!/usr/bin/env bash
# test-space-boundary.sh — proves scripts/check-space-boundary.sh FAILS the build
# on a sealed-space boundary violation, and passes on a clean tree:
#
#   clean   → guard exits 0 and prints "check-space-boundary: ok"
#   breach  → a spaces/ path staged in the PERSONAL vault index → guard exits !=0
#   leak    → a space's space-id/owner literal in a public artifact → guard exits !=0
#
# All throwaways (a fake space paspoort, a planted public leak file, a force-staged
# vault path) are removed on exit; only the test's own path is staged/reset so the
# personal vault index is left exactly as found.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${AGENTBRAIN_LOCAL_DIR:-$ROOT_DIR/local}"
GUARD="$ROOT_DIR/scripts/check-space-boundary.sh"

# The breach scenario stages paths in the vault git index. Fresh installs and
# install sandboxes have a plain (non-git) local/ — fall back to a throwaway
# git-inited vault so the guard logic still gets exercised there.
TMP_VAULT=""
if ! git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1; then
	TMP_VAULT="$(mktemp -d)"
	git -C "$TMP_VAULT" init -q
	LOCAL_DIR="$TMP_VAULT"
	export AGENTBRAIN_LOCAL_DIR="$LOCAL_DIR"
	echo "  note: local/ is not a git repo; using throwaway git vault $TMP_VAULT"
fi

SLUG="__boundarytest__"
SPACE_DIR="$LOCAL_DIR/spaces/$SLUG"
PASPOORT="$SPACE_DIR/index.md"
LEAK="$ROOT_DIR/docs/__boundarytest_leak__.md"
FAKE_ID="9c1d7e42-0000-4bcd-8aaa-deadbeef0001"
FAKE_OWNER="AcmeBoundaryTestCorp"

cleanup() {
	git -C "$LOCAL_DIR" reset -q -- "spaces/$SLUG" 2>/dev/null || true
	rm -rf "$SPACE_DIR"
	rm -f "$LEAK"
	[ -n "$TMP_VAULT" ] && rm -rf "$TMP_VAULT"
}
trap cleanup EXIT

fail() { printf 'FAIL: %b\n' "$*"; exit 1; }

[ -f "$GUARD" ] || fail "guard not found: $GUARD"

# ── 1) Clean tree → guard passes ────────────────────────────────────────────
out="$(bash "$GUARD" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "clean tree should pass, got rc=$rc\n$out"
printf '%s\n' "$out" | grep -q 'check-space-boundary: ok' || fail "missing ok line on clean run\n$out"
echo "  ok[clean]: guard passes on a clean tree"

# Plant a throwaway space paspoort with a fake space-id + owner.
mkdir -p "$SPACE_DIR"
printf -- '---\ntype: space\nslug: %s\nspace-id: %s\nowner: %s\nconfidential: true\nsync: none\ndate: 2026-06-27\n---\n# throwaway boundary-test space\n' \
	"$SLUG" "$FAKE_ID" "$FAKE_OWNER" >"$PASPOORT"

# ── 2) Seal breach (a): force-stage a spaces/ path in the personal vault index ─
git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1 || fail "local/ is not a git repo; cannot test breach"
git -C "$LOCAL_DIR" add -f "spaces/$SLUG/index.md"
out="$(bash "$GUARD" 2>&1)"; rc=$?
git -C "$LOCAL_DIR" reset -q -- "spaces/$SLUG" 2>/dev/null || true
[ "$rc" -ne 0 ] || fail "seal breach must fail the guard\n$out"
printf '%s\n' "$out" | grep -q "spaces/$SLUG" || fail "breach output must name the staged space path\n$out"
echo "  ok[breach]: spaces/ staged in vault index -> guard refuses + names it"

# Vault index must be left clean for this path.
staged="$(git -C "$LOCAL_DIR" diff --cached --name-only 2>/dev/null | grep -F "spaces/$SLUG" || true)"
[ -z "$staged" ] || fail "breach test failed to unstage throwaway path: $staged"

# ── 3) Confidential leak (b): public file carrying the fake space-id + owner ──
mkdir -p "$ROOT_DIR/docs"
printf -- '# leak probe\nspace-id %s owned by %s\n' "$FAKE_ID" "$FAKE_OWNER" >"$LEAK"
out="$(bash "$GUARD" 2>&1)"; rc=$?
rm -f "$LEAK"
[ "$rc" -ne 0 ] || fail "confidential leak must fail the guard\n$out"
printf '%s\n' "$out" | grep -q "docs/__boundarytest_leak__.md" || fail "leak output must name the offending file\n$out"
printf '%s\n' "$out" | grep -q "$FAKE_ID" || fail "leak output must report the leaked space-id\n$out"
echo "  ok[leak]: space-id/owner in a public artifact -> guard refuses + names it"

# ── 4) Back to clean after throwaways removed ────────────────────────────────
rm -rf "$SPACE_DIR"
out="$(bash "$GUARD" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "guard should pass again after cleanup, got rc=$rc\n$out"
echo "  ok[clean-again]: guard passes after throwaways removed"

echo "PASS test-space-boundary"
