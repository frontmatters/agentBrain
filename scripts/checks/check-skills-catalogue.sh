#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-skills-catalogue.sh — the add-on half of the skills catalogue agrees
# with itself, and the published registry index is told when it lags.
#
# `skills list` derives every add-on skill from the files: the add-on id is the
# skill name, the SKILL.md description is what an agent reads to pick it. So:
#
#   FAIL  an add-on SKILL.md whose frontmatter `name:` is not the add-on id
#         (the skill is linked under the id; an agent sees another name), or
#         that has no `description:` (the catalogue row and the agent's
#         trigger text are empty).
#   WARN  a registry index.json on disk that lags the manifests: an add-on is
#         missing, or its version, kind or license differs. Publishing is a
#         release step, so a lag is reported, never failed.
#
# Enabled add-ons without a skill link are check-skill-links.sh's job (it reads
# the same enabled-state and agent dirs as setup-skills.sh); not repeated here.
#
# Registry index: ADDONS_REGISTRY_INDEX (a colon-separated list of index.json
# files or registry clone dirs), else factory.json addons.registry and
# addons.registryMirror (scripts/lib/factory.sh). None configured, or a path
# that is absent: skipped, with a line saying so.
#
# Env: ADDONS_CHECK_REGISTRY  add-on root (default system/addons; tests)
# Exit codes: 0 ok (warnings allowed), 1 a FAIL above.
# Bash 3.2 compatible.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1
# shellcheck source=scripts/lib/factory.sh
. "$ROOT_DIR/scripts/lib/factory.sh"

REG="${ADDONS_CHECK_REGISTRY:-system/addons}"

# First-frontmatter field; a folded/literal scalar counts as present when a
# continuation line follows it.
fm_field() {
	awk -v k="$2" '
		/^---[[:space:]]*$/ { fm++; if (fm > 1) exit; next }
		fm != 1 { next }
		folded && /^[[:space:]]+[^[:space:]]/ { l=$0; sub(/^[[:space:]]+/, "", l); out = out (out == "" ? "" : " ") l; next }
		folded { exit }
		$0 ~ "^"k":[[:space:]]*[|>][-+]?[[:space:]]*$" { folded=1; next }
		$0 ~ "^"k":" { l=$0; sub("^"k":[[:space:]]*", "", l); sub(/[[:space:]]+$/, "", l); gsub(/^["\047]|["\047]$/, "", l); out=l; exit }
		END { print out }
	' "$1" 2>/dev/null
}

errors=0
skills=0

# ── 1. every add-on SKILL.md: name is the id, description present ────────────
for d in "$REG"/*/; do
	[ -f "${d}SKILL.md" ] || continue
	id="$(basename "$d")"
	[ "$id" = "_template" ] && continue
	skills=$((skills + 1))
	name="$(fm_field "${d}SKILL.md" name)"
	if [ -z "$name" ]; then
		echo "FAIL $id: SKILL.md has no frontmatter name (expected '$id')" >&2
		errors=$((errors + 1))
	elif [ "$name" != "$id" ]; then
		echo "FAIL $id: SKILL.md name '$name' is not the add-on id '$id' (the skill is linked as /$id)" >&2
		errors=$((errors + 1))
	fi
	if [ -z "$(fm_field "${d}SKILL.md" description)" ]; then
		echo "FAIL $id: SKILL.md has no description (empty catalogue row, nothing for an agent to match)" >&2
		errors=$((errors + 1))
	fi
done

# ── 2. registry index lag (warn only) ───────────────────────────────────────
indexes="${ADDONS_REGISTRY_INDEX:-}"
origin="ADDONS_REGISTRY_INDEX"
if [ -z "$indexes" ]; then
	origin="factory.json"
	for key in addons.registry addons.registryMirror; do
		p="$(factory_path "$key")"
		[ -n "$p" ] && indexes="${indexes:+$indexes:}$p"
	done
fi

warned=0
if [ -z "$indexes" ]; then
	echo "check-skills-catalogue: no registry index configured (ADDONS_REGISTRY_INDEX or factory.json addons.registry); registry lag not checked"
elif ! command -v python3 >/dev/null 2>&1; then
	echo "check-skills-catalogue: python3 not found; registry lag not checked"
else
	OLDIFS="$IFS"; IFS=':'
	# shellcheck disable=SC2086
	set -- $indexes
	IFS="$OLDIFS"
	for p in "$@"; do
		idx="$p"; [ -d "$idx" ] && idx="$idx/index.json"
		if [ ! -f "$idx" ]; then
			echo "check-skills-catalogue: registry index $idx absent ($origin); skipped"
			continue
		fi
		# Manifest values as registry-index.sh publishes them: license falls
		# back to Apache-2.0, kind is published as written.
		manifests="$(for m in "$REG"/*/manifest.md; do
			[ -f "$m" ] || continue
			id="$(basename "$(dirname "$m")")"
			[ "$id" = "_template" ] && continue
			lic="$(fm_field "$m" license)"
			printf '%s\t%s\t%s\t%s\n' "$id" "$(fm_field "$m" version)" "$(fm_field "$m" kind)" "${lic:-Apache-2.0}"
		done)"
		report="$(printf '%s\n' "$manifests" | python3 -c '
import json, sys
try:
    addons = json.load(open(sys.argv[1])).get("addons", [])
    idx = {a.get("id"): a for a in addons if isinstance(a, dict)}
except (OSError, ValueError, AttributeError) as e:
    print("unreadable: %s" % e); sys.exit(0)
for line in sys.stdin.read().splitlines():
    if not line:
        continue
    i, ver, kind, lic = (line.split("\t") + [""] * 4)[:4]
    a = idx.get(i)
    if a is None:
        print("%s: missing from the index" % i); continue
    d = []
    for k, want in (("version", ver), ("kind", kind), ("license", lic)):
        got = a.get(k) or ""
        if got != want:
            d.append("%s %s -> %s" % (k, got or "(none)", want or "(none)"))
    if d:
        print("%s: %s" % (i, ", ".join(d)))
' "$idx")"
		if [ -z "$report" ]; then
			echo "check-skills-catalogue: registry index $idx matches the manifests"
		else
			n="$(printf '%s\n' "$report" | wc -l | tr -d ' ')"
			echo "WARN registry index $idx lags the manifests ($n add-on(s)); regenerate with scripts/registry-index.sh at the next publish:"
			printf '%s\n' "$report" | sed 's/^/  /'
			warned=$((warned + 1))
		fi
	done
fi

if [ "$errors" -gt 0 ]; then
	echo "check-skills-catalogue: $errors problem(s) in $skills add-on skill(s)" >&2
	exit 1
fi
if [ "$warned" -gt 0 ]; then
	echo "check-skills-catalogue: $skills add-on skill(s) ok; $warned registry index(es) lagging (warning)"
else
	echo "check-skills-catalogue: $skills add-on skill(s) ok"
fi
