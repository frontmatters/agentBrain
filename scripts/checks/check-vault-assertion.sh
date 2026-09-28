#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-vault-assertion.sh — a check that reads the vault must assert it is there.
#
# The failure class this closes: scripts/lib/vault.sh answers WHERE the vault is
# and never WHETHER it exists, so a check that walks vault content in a tree
# without one finds nothing, reports ok, and exits 0. Green because it saw
# nothing, not because there was nothing to see. A full doctor run is protected
# because check-anchors fails hard on a missing vault; a single check run by
# hand, which is how a targeted fix gets validated, is not.
#
# Wiring vault_required by hand fixes instances, not the class: nothing requires
# the next check to do it, and the whole point of a false green is that nobody
# notices it.
#
# A ratchet, like .enforcement-ratchet.json: the existing backlog is frozen and
# only growth is refused, so the debt is visible and shrinking instead of
# blocking work today.
#
# An EXEMPT entry needs a MEASURED reason, not a plausible one: run the check in
# a worktree with no vault and show it already fails. "It probably fails anyway"
# is how a guard turns into decoration. Note that some checks exit non-zero there
# for an unrelated reason (check-vault-spelling exits 2 for a missing argument),
# and that is not an exemption.
#
# Usage:
#   check-vault-assertion.sh            count against the ratchet
#   check-vault-assertion.sh --list     print the checks that still lack it
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

RATCHET="scripts/checks/.vault-assertion-ratchet.json"
LIST=0
[ "${1:-}" = "--list" ] && LIST=1

# Checks exempted with a measured reason. Empty on purpose: every candidate is
# in the ratchet until someone measures it. Format: one basename per line.
EXEMPT=""

# Reading the vault: the resolved directory, or a literal path into one of its
# content directories. Comment-only mentions do not count, or a check that
# merely explains the vault would be listed for prose.
reads_vault() {
	local f="$1"
	/usr/bin/grep -vE '^[[:space:]]*#' "$f" \
		| /usr/bin/grep -qE '\$\{?VAULT_DIR\}?|\$\{?VAULT\}?/|vault/(learnings|projects|spaces|preferences|sessions|memories|specs|decisions)'
}

missing=0
missing_list=()
for f in scripts/checks/check-*.sh; do
	base="$(basename "$f")"
	[ "$base" = "check-vault-assertion.sh" ] && continue
	case "$EXEMPT" in *"$base"*) [ -n "$EXEMPT" ] && continue ;; esac
	reads_vault "$f" || continue
	/usr/bin/grep -q 'vault_required' "$f" && continue
	missing=$((missing + 1))
	missing_list+=("$base")
done

if [ "$LIST" = 1 ]; then
	printf '%s\n' "${missing_list[@]:-}" | sed '/^$/d'
fi

ceiling="$(sed -n 's/.*"unasserted" *: *\([0-9]*\).*/\1/p' "$RATCHET" 2>/dev/null || true)"
ceiling="${ceiling:-$missing}"

if [ "$missing" -gt "$ceiling" ]; then
	echo "FAIL checks that read the vault without asserting it: $ceiling -> $missing (may only fall)." >&2
	echo "  -> add: . \"\$ROOT_DIR/scripts/lib/vault.sh\"; vault_required <name> [\"\$THE_PATH_IT_READS\"] || exit \$?" >&2
	echo "  -> run with --list to see which. Exempting instead needs a measured reason; see the header." >&2
	exit 1
elif [ "$missing" -lt "$ceiling" ]; then
	echo "note: ratchet can drop $ceiling -> $missing; update $RATCHET."
fi
echo "check-vault-assertion: ok ($missing vault-reading check(s) without an assertion, ceiling $ceiling)"
