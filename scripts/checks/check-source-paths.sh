#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-source-paths.sh — every `source`/`.` line in scripts/ must point at a
# file that exists, computed from the script's OWN location.
#
# The failure this catches: a script that lives in a subdirectory of scripts/
# (tools/, release/, sync/) copies the source line from a script that lives in
# scripts/ itself, so `$(dirname "${BASH_SOURCE[0]}")/installer/prompt-helper.sh`
# resolves to scripts/tools/installer/... which does not exist. bash -n does not
# see it, shellcheck does not see it, and the script only fails when a user runs
# it. Three scripts shipped with exactly this defect and the installer surfaced
# it on a fresh machine (install-agent-clis.sh, channel.sh, move-agentbrain.sh).
#
# Method: for each source line whose target is built from ${BASH_SOURCE[0]} or
# $0, substitute the script's absolute path for that variable and evaluate the
# expression the way bash itself would, then test the result with -f. Lines
# whose target is built from a script variable ($ROOT_DIR, $VAULT, $HERE ...)
# cannot be evaluated without running the script and are skipped; their
# correctness is covered by the scripts' own tests.
#
# Lines with a `||` fallback are judged on the FIRST alternative only.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

bad=0
ok=0
skipped=0

while IFS= read -r script; do
	abs="$ROOT_DIR/$script"
	while IFS= read -r line; do
		ln="${line%%:*}"
		rest="${line#*:}"
		# strip the leading `.`/`source`, trailing comments, and any `||` fallback
		expr="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]*(\.|source)[[:space:]]+//; s/[[:space:]]*\|\|.*$//; s/[[:space:]]*(#.*)?$//; s/[[:space:]]*[0-9]?>.*$//')"
		# shellcheck disable=SC2016  # literal match on the text $0, no expansion wanted
		if [[ "$expr" != *'BASH_SOURCE'* && "$expr" != *'$0'* ]]; then
			skipped=$((skipped + 1))
			continue
		fi
		e="${expr//\$\{BASH_SOURCE\[0\]\}/$abs}"
		e="${e//\$0/$abs}"
		target="$(eval "printf '%s' $e" 2>/dev/null || true)"
		if [[ -n "$target" && -f "$target" ]]; then
			ok=$((ok + 1))
		else
			bad=$((bad + 1))
			printf '  ✗ %s:%s → %s\n' "$script" "$ln" "${target:-<unresolvable>}"
		fi
	done < <(grep -nE '^[[:space:]]*(\.|source)[[:space:]]+' "$script" || true)
done < <(find scripts -name '*.sh' -type f | sort)

if [ "$bad" -gt 0 ]; then
	echo "check-source-paths: $bad source line(s) point at a file that does not exist ($ok ok, $skipped variable-based skipped)"
	echo "  A script in a subdirectory of scripts/ needs '/..' after dirname to reach scripts/."
	exit 1
fi
echo "check-source-paths: ✅ $ok source path(s) resolve ($skipped variable-based skipped)"
