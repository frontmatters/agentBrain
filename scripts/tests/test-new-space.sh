#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-new-space.sh — new-space.sh scaffolds a valid, hygienic space passport and
# rejects bad input (invalid slug / missing owner|relation / overwrite).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SLUG="__nstest__"; REL="local/spaces/$SLUG/index"
# A throwaway vault: the test never writes into the user's own vault.
TV="$(mktemp -d)"; export AGENTBRAIN_VAULT="$TV"
trap 'rm -rf "$TV"' EXIT

bash "$ROOT_DIR/scripts/new-space.sh" "$SLUG" --owner "Test Owner" --relation client >/dev/null 2>&1
F="$TV/spaces/$SLUG/index.md"
[ -f "$F" ] || { echo "FAIL: passport not created at $F"; exit 1; }
grep -q "^type: space" "$F" || { echo "FAIL: missing 'type: space'"; exit 1; }
grep -qE "^space-id: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" "$F" \
	|| { echo "FAIL: missing/invalid space-id"; exit 1; }

# id must equal uuid5-gen of the passport path (the note-schema invariant).
want="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL")"
have="$(awk -F': ' '/^id:/{print $2; exit}' "$F")"
[ "$want" = "$have" ] || { echo "FAIL: id parity want=$want have=$have"; exit 1; }

# Must survive the same hygiene check doctor runs over spaces.
bash "$ROOT_DIR/scripts/checks/check-vault-content.sh" "local/spaces/$SLUG" >/dev/null 2>&1 \
	|| { echo "FAIL: check-vault-content rejects the scaffolded space"; exit 1; }

# Refuse to overwrite an existing passport.
if bash "$ROOT_DIR/scripts/new-space.sh" "$SLUG" --owner X --relation client >/dev/null 2>&1; then
	echo "FAIL: overwrote existing passport"; exit 1
fi
echo "PASS test-new-space"

# Invalid slugs must be rejected with no path-escape.
for bad in "../personal" "a/b" ""; do
	if bash "$ROOT_DIR/scripts/new-space.sh" "$bad" --owner X --relation client >/dev/null 2>&1; then
		echo "FAIL: invalid slug accepted: '$bad'"; exit 1
	fi
done
# new-space.sh writes into the throwaway vault, so an escape lands there too:
# "../personal" would resolve to $TV/personal, "a/b" to $TV/spaces/a.
[ ! -e "$TV/personal" ] || { echo "FAIL: path-escape created $TV/personal"; exit 1; }
[ ! -e "$TV/spaces/a" ] || { echo "FAIL: nested slug created $TV/spaces/a"; exit 1; }
# .gitignore is the fail-closed ignore new-space.sh writes on purpose.
extra=""
for e in "$TV/spaces"/* "$TV/spaces"/.[!.]*; do
	[ -e "$e" ] || continue
	case "${e##*/}" in "$SLUG" | .gitignore) ;; *) extra="$extra ${e##*/}" ;; esac
done
[ -z "$extra" ] || { echo "FAIL: rejected slug still wrote under spaces/: $extra"; exit 1; }

# Missing required flags must fail.
if bash "$ROOT_DIR/scripts/new-space.sh" "__nsx__" --relation client >/dev/null 2>&1; then
	echo "FAIL: accepted missing --owner"; exit 1   # the EXIT trap removes $TV
fi
if bash "$ROOT_DIR/scripts/new-space.sh" "__nsx__" --owner X >/dev/null 2>&1; then
	echo "FAIL: accepted missing --relation"; exit 1
fi
[ ! -e "$TV/spaces/__nsx__" ] || { echo "FAIL: a rejected call still created $TV/spaces/__nsx__"; exit 1; }
echo "PASS test-new-space-guards"
