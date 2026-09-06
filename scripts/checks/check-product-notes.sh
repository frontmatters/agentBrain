#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-product-notes.sh — validate the `kind:` and `publishes:` fields.
#
# `type:` says what class of note this is. `kind:` says what the note is ABOUT:
# a project note can describe a product, an experiment or a fork. Only a product
# is watched by pubcheck.
#
# Without this check a typo is silent. `kind: prodcut` simply drops that product
# out of monitoring, and nothing anywhere says so, which is the exact failure the
# monitoring exists to prevent.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

errors=0
scanned=0
products=0
VALID="product experiment fork"

while IFS= read -r f; do
	[ -f "$f" ] || continue
	scanned=$((scanned + 1))
	fm="$(awk '/^---[[:space:]]*$/{n++; next} n==1' "$f")"
	kind="$(printf '%s\n' "$fm" | awk '/^kind:/{sub(/^kind:[[:space:]]*/,""); print; exit}')"
	[ -n "$kind" ] || continue

	case " $VALID " in
		*" $kind "*) ;;
		*) echo "FAIL $f: kind: '$kind' is not one of: $VALID" >&2; errors=$((errors+1)); continue ;;
	esac

	[ "$kind" = product ] || continue
	products=$((products + 1))

	# Not -F': *': that separator also splits inside npm:snapcoder, so the first
	# field came back as "[npm" and every entry looked malformed.
	pub="$(printf '%s\n' "$fm" | awk '/^publishes:/{sub(/^publishes:[[:space:]]*/,""); print; exit}')"
	if [ -z "$pub" ] || [ "$pub" = "[]" ]; then
		echo "FAIL $f: kind: product without a publishes: list — nothing to check" >&2
		errors=$((errors+1)); continue
	fi

	# Every entry must be <channel>:<target>, so a malformed spec is caught here
	# rather than reported as "not checked" forever by the tool.
	# A pipe into while runs in a subshell, so a counter incremented there is lost
	# on the way out. Read from a here-string instead.
	while IFS= read -r spec; do
		spec="$(printf '%s' "$spec" | tr -d ' ')"
		[ -n "$spec" ] || continue
		case "$spec" in
			*:*) ;;
			*) echo "FAIL $f: publishes entry '$spec' has no channel prefix (npm:, git:, release:, mas:, brew:)" >&2
			   errors=$((errors + 1)) ;;
		esac
	done <<< "$(printf '%s' "$pub" | tr -d '[]' | tr ',' '\n')"
# -L, because vault/ is a symlink into ~/.agentBrain/vault. Without it find
# returns nothing and this check reports "passed" having read zero files, which
# is worse than not existing: it is a green light that means nothing.
done < <(find -L vault -name '*.md' -not -path '*/.trash/*' 2>/dev/null)

if [ "$errors" -gt 0 ]; then
	echo "check-product-notes: $errors error(s)" >&2
	exit 1
fi
# Counted during the same pass, not by a second command. Two mechanisms that can
# disagree is how a check ends up reporting a number it never measured.
echo "check-product-notes: passed ($scanned note(s) read, $products product(s))"
