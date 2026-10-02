#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-vault-spelling.sh — no new legacy local/ paths or Python path.parts partitions in code.
#
# The vault's link in the checkout is vault/; local/ is the old name, kept as
# an alias while path constructions in scripts and addons still spell it.
# Each new script copies its neighbour, so without a gate at the entry the
# count only grows.
#
# A ratchet: the existing occurrences are frozen, and only what a commit ADDS
# is refused. Three forms stay allowed because they are not paths into the
# directory: comment lines, the "local/<path>" identity strings handed to
# uuid5-gen.sh and validate-note-id.sh (a namespace token in a hash), and
# this file plus scripts/lib/vault.sh and scripts/migrate-v2.sh, which have to
# name the old spelling to retire it.
#
# Usage:
#   check-vault-spelling.sh --staged    refuse added lines with a local/ path or local path.parts partition
#   check-vault-spelling.sh --count     print how many remain in the tree (doctor, info)
#   check-vault-spelling.sh --docs      refuse prose that names local/ as the place of the vault
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1
MODE="${1:-}"
EXEMPT='^(scripts/checks/check-vault-spelling\.sh|scripts/migrate-v2\.sh|scripts/lib/vault\.sh|scripts/tests/test-vault-lib\.sh|scripts/uuid5-gen\.sh|scripts/hooks/validate-note-id\.sh|scripts/hooks/validate-staged-note-ids\.sh)$'
# A line that constructs a path with local/: not a comment, not an identity
# string, and followed by a path character so "local/ and vault/" in prose
# does not count. Regexes live in variables: brackets and quotes inside [[ =~ ]] parse
# badly when written inline.
RE_VAR='(\$\{?[A-Za-z_]+\}?|\.|~|[A-Za-z0-9_-]+)/local/[A-Za-z0-9_.$*{-]'
RE_COMMENT='^[[:space:]]*#'
RE_IDENTITY='uuid5-gen\.sh|validate-note-id|validate-staged-note-ids|brainPath\('
RE_JOIN='"local", "|Path\("local"\)|Path\('"'"'local'"'"'\)'   # join(root, "local", ...): the same path in another spelling
RE_PARTS="['\"]local['\"][[:space:]]+in[[:space:]]+[A-Za-z_.][A-Za-z0-9_.]*\\.parts"
is_path_use() {
	local l="$1"
	l="${l%% #*}"                      # a trailing comment is prose, not a path
	[[ "$l" =~ $RE_COMMENT ]] && return 1
	[[ "$l" =~ $RE_IDENTITY ]] && return 1
	[[ "$l" == */usr/local/* || "$l" == *.local/* ]] && return 1   # system paths, not the vault's old spelling
	# A line that names vault/ as well handles both spellings on purpose: an
	# exclusion for a leftover local/ tree, a glob that accepts either. The
	# --count side already treats it so; the gate refused what the count allowed.
	[[ "$l" == *vault* ]] && return 1
	# Only a path built from a variable ("$ROOT/local/x") is refused. A bare
	# "local/x" is more often a label, a message or an identity string than a
	# path, and refusing those breaks checks that use them legitimately. Bare
	# forms are counted (--count), not gated.
	[[ "$l" =~ $RE_VAR || "$l" =~ $RE_JOIN || "$l" =~ $RE_PARTS ]]
}
case "$MODE" in
--staged)
	found=0
	while IFS= read -r f; do
		[[ "$f" =~ \.(sh|py|ts|js|mjs)$ || "$f" =~ /bin/[^/.]+$ ]] || continue   # extensionless bin/ scripts are code too
		[[ "$f" =~ $EXEMPT ]] && continue
		[[ "$f" == */tests/* ]] && continue   # fixtures build local/ on purpose: the identity every id is spelled in
		while IFS= read -r line; do
			line="${line#+}"
			if is_path_use "$line"; then
				[ "$found" -eq 0 ] && echo "check-vault-spelling: a literal local/ path was added. The vault is vault/; use \$VAULT_DIR from scripts/lib/vault.sh:" >&2
				printf '  %s: %s\n' "$f" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-100)" >&2
				found=1
			fi
		done < <(git diff --cached -U0 --no-color -- "$f" | grep -E '^\+[^+]' || true)
	done < <(git diff --cached --name-only --diff-filter=ACMR)
	[ "$found" -eq 0 ] && echo "check-vault-spelling: ok (staged)"
	exit "$found"
	;;
--count)
	# What is counted: a local/ that is a path on disk. Not counted, by name:
	#   - lines that also say vault (globs that accept both spellings, folds,
	#     the mapping from the local/ identity to the vault/ directory);
	#   - the alias mechanics (setup-vault, setup-structure, migrate-v2,
	#     uninstall) and the id derivation (uuid5-gen, validate-note-id);
	#   - the MCP and the tests, where local/ is the identity every note id,
	#     search key and access record is spelled in, by design.
	n="$(find scripts system -path '*/node_modules' -prune -o -type f \( -name '*.sh' -o -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o \( -path '*/bin/*' ! -name '*.*' \) \) -print0 2>/dev/null | xargs -0 grep -nE '\blocal/|"local", |Path\("local"\)|/local(["'"'"'` )]|$)' 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' | grep -vE 'uuid5-gen\.sh|validate-note-id|validate-staged-note-ids|node_modules/|/usr/local/|\.local/' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*\*' | grep -vE '/tests/|brainPath\(' | grep -vE '^[^:]+:[0-9]+:.*(vault|localDisk|ident_with_ext|legacy flat|TRASH_BATCH/local|\$batch/local|ORIGINAL_PATHS|agentBrain/local/\{|"local/" \+ rel|personalize them in|rel === "local")' | grep -vE '\.test\.ts:' | grep -vE '^(scripts/setup/setup-vault\.sh|scripts/setup/drop-local-alias\.sh|scripts/setup/setup-structure\.sh|scripts/migrate-v2\.sh|scripts/uninstall\.sh|scripts/checks/check-vault-spelling\.sh|system/addons/agentbrain-mcp/src/|[^:]*/tests?/|[^:]*/test\.sh)' | wc -l | tr -d ' ')"
	echo "check-vault-spelling: $n literal local/ path(s) remain in code (migration to \$VAULT_DIR; the ratchet refuses new ones)"
	exit 0
	;;
--docs)
	# Prose a person reads must name the vault as vault/. A local/ there tells
	# the reader to look in a directory a current checkout does not have. A
	# line may still name local/ when it says why: the old name, the alias, the
	# identity every note id is spelled in. Changelogs are history and tests
	# build local/ on purpose; private add-ons do not ship. Exemptions by path
	# live in scripts/lib/exemptions.tsv under "vault-spelling-docs".
	docs_root="${2:-.}"
	reg="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)/lib/exemptions.tsv"
	exempt=()
	if [ -f "$reg" ]; then
		while IFS=$'\t' read -r check pattern _e _r; do
			[ "${check:-}" = "vault-spelling-docs" ] && [ -n "${pattern:-}" ] && exempt+=("$pattern")
		done < "$reg"
	fi
	# A private add-on (manifest `distribution: private`) does not ship.
	private_re="$(cd "$docs_root" && grep -lE '^distribution:[[:space:]]*private([[:space:]]|$)' system/addons/*/manifest.md 2>/dev/null | sed 's#/manifest\.md$#/#' | paste -sd'|' -)"
	hits="$(cd "$docs_root" && git ls-files -- '*.md' '*.json' '*.example' | grep -vE '(^|/)CHANGELOG\.md$|(^|/)tests?/|node_modules/' | { if [ -n "$private_re" ]; then grep -vE "^($private_re)"; else cat; fi; } | while IFS= read -r f; do
		skip=0
		for pat in ${exempt[@]+"${exempt[@]}"}; do
			# shellcheck disable=SC2254
			case "$f" in $pat) skip=1 ;; esac
		done
		[ "$skip" -eq 1 ] && continue
		grep -nE '(^|[^.A-Za-z0-9_/~-])local/' "$f" 2>/dev/null | grep -vE '/usr/local|\.local/' | grep -viE 'legacy|alias|older|old name|pre-rename|identity|spelling|rename|\bids?\b' | sed "s#^#$f:#"
	done)"
	if [ -n "$hits" ]; then
		echo "check-vault-spelling: prose names local/ as a place; the vault is vault/ (or say why local/ is meant: old name, alias, id spelling):" >&2
		printf '%s\n' "$hits" | sed 's/^/  /' >&2
		exit 1
	fi
	echo "check-vault-spelling: ok (docs)"
	exit 0
	;;
*) echo "usage: check-vault-spelling.sh --staged | --count | --docs [dir]" >&2; exit 2 ;;
esac
