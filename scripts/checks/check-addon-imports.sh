#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-addon-imports.sh — an addon's TypeScript imports stay inside the addon,
# or reach shared code as "@agentbrain/lib/*".
#
# A relative import that climbs out of the addon ("../../../lib/x",
# "../youtube-digest/src/y") only resolves where the addon happens to sit next
# to what it names. A registry addon sits in vault/addons/, an essential one in
# the slim release payload without the others: on 2026-09-07 extract-learnings
# imported youtube-digest, which is not in the payload, and the precompact hook
# silently loaded nothing on every fresh install. "@agentbrain/lib/*" resolves
# everywhere (system/addons/tsconfig.json for bundled addons, a rendered
# tsconfig for registry ones).
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1
fail=0
while IFS= read -r f; do
	addon="${f#system/addons/}"; addon="${addon%%/*}"
	dir="$(dirname "$f")"
	while IFS= read -r line; do
		spec="$(printf '%s' "$line" | grep -oE 'from "[^"]+"' | sed 's/^from "//; s/"$//')"
		[ -n "$spec" ] || continue
		case "$spec" in
			@agentbrain/lib/*) continue ;;
			./*|../*) ;;
			*) continue ;;   # a package
		esac
		# Resolve the spec against the importing file and demand it stays in the addon.
		target="$(cd "$dir" && cd -P "$(dirname "$spec")" 2>/dev/null && pwd -P)/$(basename "$spec")"
		case "$target" in
			"$ROOT/system/addons/$addon"|"$ROOT/system/addons/$addon/"*) ;;
			*) echo "  ✗ $f: '$spec' leaves system/addons/$addon (use @agentbrain/lib/* for shared code)"; fail=1 ;;
		esac
	done < <(grep -E '^(import|export) .* from "\.\.?/' "$f" 2>/dev/null)
done < <(find system/addons -type f \( -name '*.ts' -o -name '*.mjs' -o -name '*.js' \) -not -path '*/node_modules/*' -not -path '*/tests/*' -not -name '*.test.*' -not -path 'system/addons/_template/*' | sort)
if [ "$fail" -ne 0 ]; then
	echo "check-addon-imports: an addon import leaves its addon (see the header of this check)" >&2
	exit 1
fi
echo "check-addon-imports: ok (every addon import stays inside the addon or goes through @agentbrain/lib)"
