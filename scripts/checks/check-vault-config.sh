#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Ensure standalone runtime code does not bypass the configurable vault resolver.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

# These patterns are deliberately narrow: documentation may show the default, but
# executable code must resolve the user's vault through vault.sh or vaultDir().
# A negative case has to contain the defect it proves, so the register carries
# those paths with a reason, the same way check-sandbox-home does. Filtering here
# rather than in the ripgrep globs keeps the exemption visible in one file
# instead of hidden in a pattern list.
_REG="$ROOT_DIR/scripts/lib/exemptions.tsv"
_exempt_filter() {
	[ -f "$_REG" ] || { cat; return 0; }
	local line path check pattern _e _r
	while IFS= read -r line; do
		path="${line%%:*}"; path="${path#"$ROOT_DIR"/}"
		local skip=0
		while IFS=$'\t' read -r check pattern _e _r; do
			[ "${check:-}" = "check-vault-config" ] || continue
			[ -n "${pattern:-}" ] || continue
			# shellcheck disable=SC2254
			case "$path" in $pattern) skip=1; break ;; esac
		done < "$_REG"
		[ "$skip" -eq 1 ] || printf '%s\n' "$line"
	done
}

PATTERN='(\$HOME|\$\{HOME\}|~/)\.?/?agentBrain/vault|join\([^)]*(BRAIN_ROOT|BRAIN),[[:space:]]*"vault'
HITS="$(rg -n --glob '*.sh' --glob '*.ts' --glob '*.mjs' \
  --glob '!**/tests/**' --glob '!**/*.test.ts' \
  --glob '!scripts/checks/check-vault-config.sh' \
  "$PATTERN" "$ROOT_DIR/scripts" "$ROOT_DIR/system" 2>/dev/null \
  | grep -vE ':[0-9]+:[[:space:]]*(#|//|\*|echo[[:space:]]|printf[[:space:]])' \
  | _exempt_filter || true)"

if [ -n "$HITS" ]; then
  echo "check-vault-config: runtime code bypasses the configurable vault resolver:" >&2
  printf '%s\n' "$HITS" >&2
  echo "Use scripts/lib/vault.sh or the shared TypeScript vault resolver." >&2
  exit 1
fi

echo "check-vault-config: ✅ no forbidden direct vault paths in runtime code"
