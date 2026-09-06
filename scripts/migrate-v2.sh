#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# migrate-v2.sh — v2.0.0 layout migration for existing agentBrain installs.
#
#   system/ -> core/   (+ compat symlink system -> core)
#   local/  -> vault/  (+ compat symlink local -> vault)
#
# Idempotent: safe to re-run. Works in git clones AND plain copies (plain mv;
# git detects the rename at commit time). Compat symlinks keep every old path
# working — docs, muscle memory and agent invocations — while the canonical
# locations are core/ and vault/.
#
# Usage:
#   migrate-v2.sh              migrate (idempotent)
#   migrate-v2.sh --dry-run    show what would happen
#   migrate-v2.sh --verify     verify a migrated install
#   migrate-v2.sh --plan       print the migration plan for existing users
#   migrate-v2.sh --selftest   run the built-in test (temp sandbox, no risk)
set -uo pipefail

ROOT="${AB_MIGRATE_ROOT:-$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
DRY=0; VERIFY=0; PLAN=0

for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY=1 ;;
		--verify)  VERIFY=1 ;;
		--plan)    PLAN=1 ;;
		--selftest) SELFTEST=1 ;;
		-h|--help) PLAN=1 ;;
		*) echo "unknown arg: $arg" >&2; exit 1 ;;
	esac
done

plan_text() {
	cat <<'PLAN'
Migratieplan voor bestaande installs (v2.0.0):

  0. Voorwaarden: geen on-committe wijzigingen binnen system/ of local/
     (commit of stash eerst). Script aborteert automatisch bij twijfel.
  1. Dit script draaien (idempotent): verplaatst system/ -> core/ en
     local/ -> vault/ en legt compat-symlinks op de oude paden.
  2. Na de migrate: git add -A && git commit (git-installs; git detecteert
     de rename vanzelf). Geen git? De compat-symlinken dekken alles.
  3. doctor draaien voor de health-check (setup-phase: "pending" is normaal
     op een verse install).
  4. Tweede machine: eerst syncen, dan daar hetzelfde script draaien.

Rollback: verwijder de symlinks system en local, en
  mv core system && mv vault local
(doen vóór de eerste commit/_push na de migratie).
PLAN
}

migrate_pair() { # migrate_pair <old> <new> <label>
	local old="$1" new="$2" label="$3"
	if [ -L "$ROOT/$old" ]; then
		# symlink: herleid — nieuw naamloze link naar hetzelfde target,
		# oude pad wordt compat-link naar de nieuwe naam.
		local target; target="$(readlink "$ROOT/$old")"
		dry_run "symlink $old -> $new (target: $target)"
		[ $DRY -eq 1 ] && return 0
		ln -sfn "$target" "$ROOT/$new"
		ln -sfn "$new" "$ROOT/$old"
		return 0
	fi
	if [ -d "$ROOT/$old" ] && [ ! -e "$ROOT/$new" ]; then
		dry_run "mv $old $new + compat-symlink $old -> $new"
		[ $DRY -eq 1 ] && return 0
		mv "$ROOT/$old" "$ROOT/$new"
		ln -sfn "$new" "$ROOT/$old"
		return 0
	fi
	if [ -d "$ROOT/$new" ] && [ ! -e "$ROOT/$old" ]; then
		echo "  $new bestaat al, $old niet gevonden: al gemigreerd."
		return 0
	fi
	if [ -e "$ROOT/$old" ] && [ -e "$ROOT/$new" ]; then
		echo "  MEERDUIDIG: $old én $new bestaan. Los handmatig op (houd één, " \
			"merge inhoud), draai daarna opnieuw." >&2
		exit 3
	fi
	echo "  $old niet gevonden — niets te doen voor $label."
	return 0
}

dry_run() { [ $DRY -eq 1 ] && echo "  (dry) $*" || true; }

gitignore_note() { # nieuwe naam naast (niet i.p.v.) de oude ignore-regel
	local new="$1" gitignore="$ROOT/.gitignore"
	[ $DRY -eq 1 ] && return 0
	[ -f "$gitignore" ] || return 0
	if grep -qE "^${new}/?\$" "$gitignore"; then return 0; fi
	if grep -qE "^${new%%/*}(/|\$)" "$gitignore"; then return 0; fi
	echo "$new/" >> "$gitignore"
	echo "  .gitignore: $new/ toegevoegd (was niet genegeerd)"
}

verify() {
	local rc=0
	if [ -e "$ROOT/core" ]; then echo "  ✓ core/"; else echo "  ✗ core/ ontbreekt"; rc=1; fi
	if [ -e "$ROOT/vault" ]; then echo "  ✓ vault/"; else echo "  ✗ vault/ ontbreekt"; rc=1; fi
	[ -L "$ROOT/system" ] && echo "  ✓ compat-symlink system -> $(readlink "$ROOT/system")" || echo "  ⚠ geen compat-symlink system"
	[ -L "$ROOT/local" ] && echo "  ✓ compat-symlink local -> $(readlink "$ROOT/local")" || echo "  ⚠ geen compat-symlink local"
	[ -f "$ROOT/core/rules.md" ] && echo "  ✓ core/rules.md spot-check" || echo "  ⚠ core/rules.md niet gevonden (spot-check)"
	return $rc
}

run_migration() {
	echo "root: $ROOT"
	[ -d "$ROOT/system" ] || [ -L "$ROOT/system" ] || [ -d "$ROOT/core" ] || {
		echo "geen system/ of core/ gevonden — is dit een agentBrain-install?" >&2
		exit 4
	}
	echo "-- migratie --"
	migrate_pair system core "framework"
	migrate_pair local vault "private vault"
	gitignore_note vault
	echo "-- verify --"
	verify
	[ $DRY -eq 1 ] && { echo "(dry-run — niets gewijzigd)"; return 0; }
	echo ""
	echo "Volgende stap (git-install):"
	echo "  git add -A && git commit -m 'chore: v2.0.0 layout migration (core + vault)'"
}

selftest() {
	local t; t="$(mktemp -d)"
	mkdir -p "$t/system" "$t/local"
	echo rules > "$t/system/rules.md"
	echo notes > "$t/vault/notes.md"
	AB_MIGRATE_ROOT="$t" "$0" --dry-run >/dev/null 2>&1 || { echo "selftest: dry-run faalde" >&2; rm -rf "$t"; return 1; }
	AB_MIGRATE_ROOT="$t" "$0" >/dev/null || { echo "selftest: migrate faalde" >&2; rm -rf "$t"; return 1; }
	local ok=1
	[ -f "$t/core/rules.md" ] || { echo "FAIL core/rules.md" >&2; ok=0; }
	[ -f "$t/vault/notes.md" ] || { echo "FAIL vault/notes.md" >&2; ok=0; }
	[ -L "$t/system" ] || { echo "FAIL compat system" >&2; ok=0; }
	[ -L "$t/local" ] || { echo "FAIL compat local" >&2; ok=0; }
	[ -f "$t/vault/notes.md" ] || { echo "FAIL compat local leest inhoud" >&2; ok=0; }
	AB_MIGRATE_ROOT="$t" "$0" >/dev/null 2>&1 || { echo "FAIL idempotente rerun" >&2; ok=0; }
	if [ "$ok" -eq 1 ]; then echo "selftest: ok (temp: $t)"; else echo "selftest: FAILED" >&2; rm -rf "$t"; return 1; fi
	rm -rf "$t"
}

if [ "${SELFTEST:-}" = 1 ]; then
	selftest
	exit $?
fi

if [ $PLAN -eq 1 ]; then
	plan_text
	exit 0
fi

if [ $VERIFY -eq 1 ]; then
	verify
	exit $?
fi

run_migration
