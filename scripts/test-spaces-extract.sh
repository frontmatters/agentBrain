#!/usr/bin/env bash
# test-spaces-extract.sh — brain-extract --space bundles a space stamped with its
# space-id, and brain-restore --space round-trips it back under local/spaces/<slug>/.
# Also asserts brain-restore REFUSES path-escape ('..') / absolute targets carried
# by hostile-but-checksum-valid space packages, writing nothing outside the space.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG="__extest__"; SP="$ROOT_DIR/local/spaces/$SLUG"
OUT="$(mktemp -d)"; RV="$(mktemp -d)"
# Hostile-case sandboxes. Throwaway vaults live INSIDE $HSB so we can also assert
# that nothing escaped ABOVE the vault root (which lands directly in $HSB).
HSB="$(mktemp -d)"; HPKGROOT="$(mktemp -d)"
trap 'rm -rf "$SP" "$OUT" "$RV" "$HSB" "$HPKGROOT"' EXIT
mkdir -p "$SP"
SID="11111111-2222-4333-8444-555555555555"
NID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/spaces/$SLUG/index")"
printf -- '---\ntype: space\nslug: %s\nspace-id: %s\nid: %s\nowner: Test\nrelation: client\nconfidential: true\nsync: none\ntags: [space]\ndate: 2026-06-26\n---\n# %s\n' "$SLUG" "$SID" "$NID" "$SLUG" > "$SP/index.md"

# --vault pins the run to this checkout's vault so the test is independent of which
# checkout ~/agentBrain currently points at.
bash "$ROOT_DIR/system/skills/brain-extract/bin/brain-extract" --space "$SLUG" --out "$OUT" --vault "$ROOT_DIR/local" >/dev/null 2>&1
PKG="$(find "$OUT" -name 'manifest.yml' -o -name 'space.yml' | head -1)"
[ -n "$PKG" ] || { echo "FAIL: no package manifest produced"; exit 1; }
grep -q "$SID" "$PKG" || { echo "FAIL: package not stamped with space-id $SID"; exit 1; }

# Round-trip: restore the package into a throwaway vault and confirm the note lands
# back under spaces/<slug>/ (and nowhere else).
PKG_DIR="$(dirname "$PKG")"
bash "$ROOT_DIR/system/skills/brain-restore/bin/brain-restore" "$PKG_DIR" --space --vault "$RV" >/dev/null 2>&1
[ -f "$RV/spaces/$SLUG/index.md" ] || { echo "FAIL: restore did not land note under spaces/$SLUG/"; exit 1; }
grep -q "$SID" "$RV/spaces/$SLUG/index.md" || { echo "FAIL: restored note missing space-id"; exit 1; }

# === Hostile packages: path-escape ('..') in a space note must be refused ======
HSLUG="__exhostile__"
HSID="99999999-8888-4777-8666-555555555555"

# build_hostile_pkg <vault-rel-target-with-dotdot> <pkgdir>
# Crafts a checksum-valid .brain-package whose single space note maps (by UUID5 of
# its path) to an out-of-space target. manifest_validate passes ('..' is not an
# absolute path) and CHECKSUMS pass — so only brain-restore's own guard can stop
# it. The note is named with the same UUID5 brain-restore derives for the target,
# so the note actually maps and the path-escape guard (not the "cannot map"
# branch) is what triggers the refusal.
build_hostile_pkg() {
  local target="$1" pkgdir="$2"
  rm -rf "$pkgdir"; mkdir -p "$pkgdir/notes"
  local rel_no_ext hid
  rel_no_ext="${target%.md}"
  hid="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/$rel_no_ext")"
  printf -- '---\ntype: learning\nid: %s\ntags: [pwned]\ndate: 2026-06-26\n---\n# PWNED\n' "$hid" > "$pkgdir/notes/$hid.md"
  {
    echo "version: 1"
    echo "project: $HSLUG"
    echo "slug: $HSLUG"
    echo "space_id: $HSID"
    echo "kind: space"
    echo "include:"
    echo "  - $target"
    echo "exclude: []"
  } > "$pkgdir/manifest.yml"
  : > "$pkgdir/CHECKSUMS.txt"
  ( cd "$pkgdir" && for f in notes/*.md manifest.yml; do
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk -v p="$f" '{print $1 "  " p}'
      else
        shasum -a 256 "$f" | awk -v p="$f" '{print $1 "  " p}'
      fi
    done ) >> "$pkgdir/CHECKSUMS.txt"
}

# assert_refused <label> <target> [in-vault-rel-escaped] [abs-escaped]
assert_refused() {
  local label="$1" target="$2" in_vault_rel="${3:-}" abs_escaped="${4:-}"
  local vault pkg out rc
  vault="$(mktemp -d "$HSB/vault.XXXXXX")"
  pkg="$HPKGROOT/${label}.brain-package"
  build_hostile_pkg "$target" "$pkg"
  out="$(bash "$ROOT_DIR/system/skills/brain-restore/bin/brain-restore" "$pkg" --space --vault "$vault" 2>&1)"
  rc=$?

  # (1) must exit non-zero
  if [ "$rc" -eq 0 ]; then
    echo "FAIL[$label]: brain-restore accepted hostile package (exit 0)"; echo "$out"; exit 1
  fi
  # (2) must refuse via the path-escape guard (proves the note mapped + reached
  #     the guard, not the harmless "cannot map" branch)
  echo "$out" | grep -q "unsafe space note path" || {
    echo "FAIL[$label]: not refused by the path-escape guard"; echo "$out"; exit 1; }
  # (3) nothing written anywhere under the throwaway vault except spaces/<slug>/
  if find "$vault" -type f ! -path "$vault/spaces/$HSLUG/*" -print | grep -q .; then
    echo "FAIL[$label]: file(s) written outside spaces/$HSLUG/ in vault:"; find "$vault" -type f; exit 1
  fi
  # (4) explicit in-vault escape target must not exist
  if [ -n "$in_vault_rel" ] && [ -e "$vault/$in_vault_rel" ]; then
    echo "FAIL[$label]: in-vault escape: $vault/$in_vault_rel exists"; exit 1
  fi
  # (5) explicit above-vault escape target must not exist
  if [ -n "$abs_escaped" ] && [ -e "$abs_escaped" ]; then
    echo "FAIL[$label]: above-vault escape: $abs_escaped exists"; exit 1
  fi
  echo "  ok[$label]: refused (exit $rc), nothing written outside spaces/$HSLUG/"
}

# Case A: '..' escape that stays inside the vault but leaves the space tree.
#   Vulnerable code wrote $vault/learnings/pwned.md at the atomic swap.
assert_refused "dotdot-in-vault" "spaces/$HSLUG/../../learnings/pwned.md" "learnings/pwned.md" ""

# Case B: '..' chain that escapes ABOVE the vault root entirely.
#   Vulnerable code wrote $HSB/escaped.md during staging (before any abort).
assert_refused "dotdot-above-vault" "spaces/$HSLUG/../../../../escaped.md" "" "$HSB/escaped.md"

echo "PASS test-spaces-extract"
