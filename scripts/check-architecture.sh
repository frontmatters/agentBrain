#!/usr/bin/env bash
# check-architecture.sh — Guard the canonical docs against path-drift.
# Structural checks (frontmatter/links) cannot verify that the prose describes reality.
# Three guards:
#   1. every repo-relative path named (in backticks) in system/architecture.md,
#      README.md, and system/reference.md actually exists;
#   2. every tracked top-level directory is mentioned in system/architecture.md
#      (reverse inventory — the layout section cannot silently omit a folder);
#   3. skills-home invariant: system/skills/ is the source, .github/skills/ only links.
# Scope of (1): dir-qualified repo paths only. Skips placeholders (<...>), globs (*),
# external (~) and qualified refs (:), and bare filenames (too ambiguous to resolve).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOCS=("system/architecture.md" "README.md" "system/reference.md")
errors=0

# ── 1. Backticked-path existence check, per doc ──
check_doc_paths() {
	local doc="$1" ref
	while IFS= read -r ref; do
		if [ ! -e "$ref" ]; then
			case "$ref" in
				# local/ is per-machine user runtime state, legitimately absent in a
				# fresh install (e.g. local/addons appears only once an addon is
				# installed). Documenting it must not fail doctor.
				local/*) continue ;;
				# Dev/release tooling is documented for maintainers but stripped from
				# the release payload — keep in sync with NONSHIP_SCRIPTS in release.sh.
				scripts/publish-addon.sh | scripts/publish-agentbrain-github.sh | scripts/mirror-registry-github.sh | scripts/bump-version.sh | scripts/release.sh | scripts/publish-gitea-release.sh | scripts/dev-sync-status.sh | scripts/deploy-dev-to-live.sh | scripts/release-check.sh | scripts/validate-install.sh) continue ;;
				*) echo "FAIL $doc names a path that does not exist: $ref" >&2; errors=$((errors + 1)) ;;
			esac
		fi
	done < <(
		# shellcheck disable=SC2016  # backticks are literal regex chars here, not command substitution
		grep -oE '`[^`]+`' "$doc" | tr -d '`' |
			sed -E 's/[[:space:]].*$//' |   # backticked commands: keep the path, drop args/flags
			grep -E '^(system|scripts|local|templates|learnings|projects|docs|tests|\.github)/' |
			grep -vE '[*<>~:{}]' |   # skip globs, placeholders, external (~), qualified (:) and brace-shorthand
			sed -E 's#/+$##' |
			sort -u
	)
}

for doc in "${DOCS[@]}"; do
	if [ ! -f "$doc" ]; then
		echo "check-architecture: $doc missing" >&2
		exit 1
	fi
	check_doc_paths "$doc"
done

# ── 2. Reverse inventory: tracked top-level dirs must appear in architecture.md ──
# Vendor/editor dirs are links or tool state, not architecture; whitelist them.
ARCH_DOC="system/architecture.md"
INVENTORY_WHITELIST=".github .githooks .obsidian .claude"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	while IFS= read -r dir; do
		[ -d "$dir" ] || continue   # top-level files (README.md, VERSION, …) are not inventory
		case " $INVENTORY_WHITELIST " in *" $dir "*) continue ;; esac
		if ! grep -qF "$dir/" "$ARCH_DOC"; then
			echo "FAIL tracked top-level directory not mentioned in $ARCH_DOC: $dir/" >&2
			errors=$((errors + 1))
		fi
	done < <(git ls-files | cut -d/ -f1 | sort -u)
fi

# ── 3. Skills-home invariant (architecture.md §5) ──
# The agnostic home is system/skills/; .github/skills/ may only hold symlinks into it,
# never the source itself — so skills cannot drift back into a vendor directory.
if [ ! -d system/skills ]; then
	echo "FAIL system/skills/ (the agnostic skills home) is missing" >&2
	errors=$((errors + 1))
fi
if [ -d .github/skills ]; then
	for entry in .github/skills/*; do
		[ -e "$entry" ] || continue
		if [ ! -L "$entry" ]; then
			echo "FAIL $entry is not a symlink — skills live in system/skills/; .github/skills/ may only link in" >&2
			errors=$((errors + 1))
		fi
	done
fi

if [ "$errors" -gt 0 ]; then
	echo "check-architecture: $errors issue(s) in ${DOCS[*]} / inventory / skills layout — update the doc or the code" >&2
	exit 1
fi
echo "check-architecture: all repo paths named in ${DOCS[*]} exist; top-level inventory covered; skills home is agnostic"
