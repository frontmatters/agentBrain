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
Migration plan for existing installs (v2.0.0):

  0. Preconditions: no uncommitted changes inside system/ or local/
     (commit or stash first). The script aborts automatically when in doubt.
  1. Run this script (idempotent): moves system/ -> core/ and
     local/ -> vault/ and places compat symlinks on the old paths.
  2. After the migration: git add -A && git commit (git installs; git detects
     the rename on its own). No git? The compat symlinks cover everything.
  3. Run doctor for the health check (setup-phase: "pending" is normal
     on a fresh install).
  4. Second machine: sync first, then run the same script there.

Rollback: remove the symlinks system and local, and
  mv core system && mv vault local
(do this before the first commit or push after the migration).
PLAN
}

migrate_pair() { # migrate_pair <old> <new> <label>
	local old="$1" new="$2" label="$3"
	if [ -L "$ROOT/$old" ]; then
		# symlink: re-point. The new name links to the same target,
		# the old path becomes a compat link to the new name.
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
		echo "  $new already exists, $old not found: already migrated."
		return 0
	fi
	if [ -e "$ROOT/$old" ] && [ -e "$ROOT/$new" ]; then
		echo "  AMBIGUOUS: both $old and $new exist. Resolve by hand (keep one, " \
			"merge the contents), then run again." >&2
		exit 3
	fi
	echo "  $old not found: nothing to do for $label."
	return 0
}

dry_run() { [ $DRY -eq 1 ] && echo "  (dry) $*" || true; }

gitignore_note() { # new name next to (not instead of) the old ignore rule
	local new="$1" gitignore="$ROOT/.gitignore"
	[ $DRY -eq 1 ] && return 0
	[ -f "$gitignore" ] || return 0
	if grep -qE "^${new}/?\$" "$gitignore"; then return 0; fi
	if grep -qE "^${new%%/*}(/|\$)" "$gitignore"; then return 0; fi
	echo "$new/" >> "$gitignore"
	echo "  .gitignore: added $new/ (was not ignored)"
}

verify() {
	local rc=0
	if [ -e "$ROOT/core" ]; then echo "  ✓ core/"; else echo "  ✗ core/ missing"; rc=1; fi
	if [ -e "$ROOT/vault" ]; then echo "  ✓ vault/"; else echo "  ✗ vault/ missing"; rc=1; fi
	[ -L "$ROOT/system" ] && echo "  ✓ compat-symlink system -> $(readlink "$ROOT/system")" || echo "  ⚠ no compat symlink system"
	[ -L "$ROOT/local" ] && echo "  ✓ compat-symlink local -> $(readlink "$ROOT/local")" || echo "  ⚠ no compat symlink local"
	[ -f "$ROOT/core/rules.md" ] && echo "  ✓ core/rules.md spot-check" || echo "  ⚠ core/rules.md not found (spot-check)"
	return $rc
}

run_migration() {
	echo "root: $ROOT"
	[ -d "$ROOT/system" ] || [ -L "$ROOT/system" ] || [ -d "$ROOT/core" ] || {
		echo "no system/ or core/ found: is this an agentBrain install?" >&2
		exit 4
	}
	echo "-- migration --"
	migrate_pair system core "framework"
	migrate_pair local vault "private vault"
	gitignore_note vault
	echo "-- verify --"
	verify
	[ $DRY -eq 1 ] && { echo "(dry-run: nothing changed)"; return 0; }
	echo ""
	echo "Next step (git install):"
	echo "  git add -A && git commit -m 'chore: v2.0.0 layout migration (core + vault)'"
}

selftest() {
	local t; t="$(mktemp -d)"
	mkdir -p "$t/system" "$t/local"
	echo rules > "$t/system/rules.md"
	echo notes > "$t/local/notes.md"
	SELFTEST=0 AB_MIGRATE_ROOT="$t" "$0" --dry-run >/dev/null 2>&1 || { echo "selftest: dry-run failed" >&2; rm -rf "$t"; return 1; }
	SELFTEST=0 AB_MIGRATE_ROOT="$t" "$0" >/dev/null || { echo "selftest: migrate failed" >&2; rm -rf "$t"; return 1; }
	local ok=1
	[ -f "$t/core/rules.md" ] || { echo "FAIL core/rules.md" >&2; ok=0; }
	[ -f "$t/vault/notes.md" ] || { echo "FAIL vault/notes.md" >&2; ok=0; }
	[ -L "$t/system" ] || { echo "FAIL compat system" >&2; ok=0; }
	[ -L "$t/local" ] || { echo "FAIL compat local" >&2; ok=0; }
	[ -f "$t/local/notes.md" ] || { echo "FAIL compat local reads contents" >&2; ok=0; }
	SELFTEST=0 AB_MIGRATE_ROOT="$t" "$0" >/dev/null 2>&1 || { echo "FAIL idempotent rerun" >&2; ok=0; }
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
