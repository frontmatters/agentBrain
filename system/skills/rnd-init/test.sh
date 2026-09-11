#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test.sh — rnd-init scaffolds, and then keeps its hands off.
#
# A scaffold runs more than once: on setup, after a clone, when someone adds the
# optional folders later. Between runs people edit what it produced. So the
# assertions are mostly about restraint: a second run changes nothing, an edited
# README survives, .gitignore does not grow a duplicate line, and the folders
# that must stay out of git stay out.
set -uo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
RND_INIT="$HERE/bin/rnd-init"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-rnd-init.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

R="$TMP/repo"
mkdir -p "$R"
printf 'node_modules/\n' > "$R/.gitignore"

run() { bash "$RND_INIT" --dir "$R" "$@" 2>&1; }

# --- 1. the layout appears ---------------------------------------------------
run >/dev/null
for sub in dashboards decisions captures renders logs experiments; do
	[ -d "$R/R&D/$sub" ] || bad "missing R&D/$sub"
done
[ -f "$R/R&D/README.md" ] && ok "the layout and its README are created" || bad "no R&D/README.md"

# --- 2. keep files only where they can be committed --------------------------
# captures/ and renders/ are git-ignored, so a .gitkeep there could never be
# committed and would only be noise.
[ -f "$R/R&D/decisions/.gitkeep" ] \
	&& ok "a tracked folder carries .gitkeep so it survives a clone" \
	|| bad "tracked folder has no .gitkeep"
[ ! -f "$R/R&D/captures/.gitkeep" ] \
	&& ok "an ignored folder carries no pointless .gitkeep" \
	|| bad "ignored folder got a .gitkeep that can never be committed"

# --- 3. the ignore lines land, exactly once ----------------------------------
grep -qxF 'R&D/captures/' "$R/.gitignore" && ok "captures/ is ignored" || bad "captures/ not ignored"
grep -qxF 'node_modules/' "$R/.gitignore" && ok "the existing .gitignore is preserved" || bad "clobbered .gitignore"

# --- 4. a second run is a no-op ----------------------------------------------
before="$(find "$R" -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256)"
out="$(run)"
after="$(find "$R" -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256)"
[ "$before" = "$after" ] && ok "a second run changes nothing" || bad "a second run modified the repo"
case "$out" in *"0 created"*) ok "a second run reports it created nothing" ;; *) bad "second run did not report 0 created" ;; esac
[ "$(grep -cxF 'R&D/captures/' "$R/.gitignore")" = "1" ] \
	&& ok "the ignore line is not duplicated" \
	|| bad "duplicate ignore line after rerun"

# --- 5. an edited README is never overwritten --------------------------------
# Projects add their own rules (retention, naming). Losing them is the failure
# this scaffold must not have.
printf '\nPROJECT RULE: captures are pruned after 30 days.\n' >> "$R/R&D/README.md"
run >/dev/null
grep -q "PROJECT RULE" "$R/R&D/README.md" \
	&& ok "a hand-edited README survives" \
	|| bad "the scaffold overwrote an edited README"

# --- 6. extras are opt-in ----------------------------------------------------
[ ! -d "$R/R&D/prototypes" ] && ok "optional folders are absent by default" || bad "created an optional folder unasked"
run --with prototypes >/dev/null
[ -d "$R/R&D/prototypes" ] && ok "--with creates the optional folder" || bad "--with did not create prototypes"

# --- 7. dry run writes nothing -----------------------------------------------
D="$TMP/dry"; mkdir -p "$D"
bash "$RND_INIT" --dir "$D" --dry-run >/dev/null 2>&1
[ -z "$(find "$D" -mindepth 1 2>/dev/null)" ] \
	&& ok "a dry run writes nothing" \
	|| bad "dry run created files"

# --- 8. migration moves data, never deletes it -------------------------------
M="$TMP/legacy"; mkdir -p "$M/verif-output/2026-01-01-axe"
printf 'evidence\n' > "$M/verif-output/2026-01-01-axe/shot.txt"
bash "$RND_INIT" --dir "$M" --migrate-verif-output >/dev/null 2>&1
[ -f "$M/R&D/captures/2026-01-01-axe/shot.txt" ] && ok "migration moves the artefacts" || bad "migration lost the artefacts"
[ -L "$M/verif-output" ] && ok "the old path still resolves through a symlink" || bad "verif-output is not a symlink"
[ "$(cat "$M/verif-output/2026-01-01-axe/shot.txt" 2>/dev/null)" = "evidence" ] \
	&& ok "old paths keep reading the same bytes" \
	|| bad "the old path no longer reads the artefact"

# Without the flag it must only advise, never move anything.
N="$TMP/nomig"; mkdir -p "$N/verif-output"
printf 'x\n' > "$N/verif-output/keep.txt"
out="$(bash "$RND_INIT" --dir "$N" 2>&1)"
[ -f "$N/verif-output/keep.txt" ] && [ ! -L "$N/verif-output" ] \
	&& ok "migration never happens without the flag" \
	|| bad "moved data without --migrate-verif-output"
case "$out" in *"--migrate-verif-output"*) ok "it names the flag that would migrate" ;; *) bad "did not mention the migration flag" ;; esac

printf 'rnd-init: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
