#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-cmdb-coverage.sh — ADVISORY CMDB coverage audit. Never fails (exit 0), never
# wired into doctor.sh: infrastructure is per-machine, so this must not break another
# machine's shared doctor. Reports CIs with no relationships, and git remote hosts of
# the two default checkouts that have no matching device note.
set -euo pipefail
# shellcheck source=scripts/lib/vault.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/vault.sh"
LOCAL_DIR="$VAULT_DIR"
SPACE=""
if [ "${1:-}" = "--space" ]; then
	[ -n "${2:-}" ] || { echo "check-cmdb-coverage: --space requires a slug argument" >&2; exit 2; }
	SPACE="$2"; shift 2
fi
SPACE="${SPACE:-${AGENTBRAIN_CONTEXT:-${AGENTBRAIN_SPACE:-}}}"
if [ -n "$SPACE" ]; then CI_BASE="$LOCAL_DIR/spaces/$SPACE"; else CI_BASE="$LOCAL_DIR"; fi
CI_DIRS=("$CI_BASE/devices" "$CI_BASE/integrations")
PROJECTS_DIR="$CI_BASE/projects"

_ci_field() {  # <file> -> the ci: value (empty if none)
	awk '/^---[[:space:]]*$/{fm++; next} fm==1 && /^ci:[[:space:]]/{sub(/^ci:[[:space:]]*/,""); gsub(/[[:space:]]/,""); print; exit}' "$1"
}

_has_relation() {  # <file> -> 0 if any of the 3 relation fields present IN FRONTMATTER
	# Frontmatter-scoped to match brain-cmdb's _relfield: a `hosted_on:`-looking line
	# in the note BODY (e.g. an example) must not count as a real relation, or the two
	# CMDB tools would give contradictory answers for the same note.
	awk '
		/^---[[:space:]]*$/ { fm++; next }
		fm==1 && /^(hosted_on|depends_on|provides):/ { found=1; exit }
		END { exit !found }
	' "$1"
}

echo "CMDB coverage (advisory) — ${SPACE:+space:$SPACE }$CI_BASE"

# 1. CIs with no relationships.
found_orphan=0
for d in "${CI_DIRS[@]}"; do
	[ -d "$d" ] || continue
	for f in "$d"/*.md; do
		[ -f "$f" ] || continue
		case "$(basename "$f")" in index.md|README.md) continue ;; esac
		if ! _has_relation "$f"; then
			echo "  · $(basename "$f" .md) (no relations)"; found_orphan=1
		fi
	done
done
if [ "$found_orphan" -eq 0 ]; then
	echo "  all CIs carry at least one relation."
fi

# Opted-in project CIs (carry a ci: field) with no relationships.
if [ -d "$PROJECTS_DIR" ]; then
	for f in "$PROJECTS_DIR"/*/index.md; do
		[ -f "$f" ] || continue
		[ -n "$(_ci_field "$f")" ] || continue
		if ! _has_relation "$f"; then
			echo "  · $(basename "$(dirname "$f")") (no relations)"
		fi
	done
fi

# 2. Heuristic: git remote hosts with no device note (best-effort; skipped if the
#    checkouts aren't present). Personal-context only — it inspects the two default
#    personal checkouts, which is meaningless during a --space audit, so skip it there.
if [ -z "$SPACE" ]; then
	for repo in "$HOME/Developer/agentBrain-dev" "$HOME/Developer/agentBrain"; do
		[ -d "$repo/.git" ] || continue
		url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
		host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#/.*$##; s#:[0-9]+$##; s#.*@##')"
		[ -n "$host" ] || continue
		if ! ls "$LOCAL_DIR/devices/"*.md >/dev/null 2>&1 || ! grep -rqiF "$host" "$LOCAL_DIR/devices/" 2>/dev/null; then
			echo "  · remote host '$host' ($(basename "$repo")) has no device note"
		fi
	done
fi

echo "check-cmdb-coverage: advisory only, nothing enforced."
exit 0
