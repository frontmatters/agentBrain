#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test.sh — the skills catalogue (`skills list`, `skills list --json`).
# Every skill shows up: system, local, and the skill of EVERY add-on that ships
# a SKILL.md, enabled or not, with source, state and kind read from the files.
# Runs against a throwaway brain, vault, HOME and add-on state; the real ones
# are never read. SKILLS_BIN overrides the CLI under test (negative control).
set -uo pipefail

HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
BIN="${SKILLS_BIN:-$HERE/bin/skills}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
B="$TMP/brain"; V="$TMP/vault"
mkdir -p "$B/system/skills" "$B/system/addons" "$V/skills" "$V/addons" "$TMP/home"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1" >&2; fail=$((fail+1)); }

skill() {  # <dir> <name> <description-line(s)...>
	local dir="$1" name="$2"; shift 2
	mkdir -p "$dir"
	{ echo "---"; echo "name: $name"; for l in "$@"; do echo "$l"; done; echo "---"; echo "# $name"; } > "$dir/SKILL.md"
}
addon() {  # <root> <id> <kind>
	mkdir -p "$1/$2"
	printf -- '---\nid: %s\nname: %s\nversion: 1.0.0\nkind: %s\n---\n' "$2" "$2" "$3" > "$1/$2/manifest.md"
}

skill "$B/system/skills/alpha" alpha "description: Alpha does a."
skill "$B/system/skills/beta"  beta  "description: >-" "  Beta folds" "  over two lines."
skill "$B/system/skills/_shared" _shared "description: not a skill"
skill "$V/skills/mine" mine "description: 'A private one.'"
addon "$B/system/addons" on-addon adapter;  skill "$B/system/addons/on-addon" on-addon "description: Enabled add-on."
addon "$B/system/addons" off-addon vendored; skill "$B/system/addons/off-addon" off-addon "description: Available add-on."
addon "$B/system/addons" no-skill framework   # ships no SKILL.md: not a skill
# A vault-installed copy wins over the bundled one of the same id.
addon "$V/addons" off-addon framework; skill "$V/addons/off-addon" off-addon "description: Installed copy."
mkdir -p "$V/addons/on-addon"; : > "$V/addons/on-addon/enabled"

run() { env -i PATH="$PATH" HOME="$TMP/home" AGENTBRAIN_HOME="$B" AGENTBRAIN_VAULT="$V" bash "$BIN" "$@" 2>&1; }

out="$(run list)"; rc=$?
[ "$rc" = 0 ] && ok "list exits 0" || bad "list rc=$rc: $out"

# row <name> <source> <state> <kind> <desc-fragment>: one line with all columns.
row() {
	if printf '%s\n' "$out" | grep -E "^  /$1 +$2 +$3 +$4 +.*$5" >/dev/null; then ok "row $1 $2 $3 $4"
	else bad "row $1 $2 $3 $4 '$5' missing in:"; printf '%s\n' "$out" | sed 's/^/      /' >&2; fi
}
row alpha     system installed - "Alpha does a."
row beta      system installed - "Beta folds over two lines."
row mine      local  installed - "A private one."
row on-addon  addon  enabled   adapter "Enabled add-on."
row off-addon addon  available framework "Installed copy."

printf '%s\n' "$out" | grep -q '/_shared' && bad "_shared listed" || ok "_shared not listed"
printf '%s\n' "$out" | grep -q '/no-skill' && bad "add-on without SKILL.md listed" || ok "add-on without SKILL.md not listed"
[ "$(printf '%s\n' "$out" | grep -c '/off-addon')" = 1 ] && ok "a vault copy shadows the bundled one" || bad "off-addon listed twice"
printf '%s\n' "$out" | grep -q '^5 skills: 2 system, 1 local, 2 addon (1 enabled, 1 available)$' \
	&& ok "summary line counts" || bad "summary line wrong"

# ADDONS_STATE overrides where enabled-state lives, as in addons.sh.
mkdir -p "$TMP/state/off-addon"; : > "$TMP/state/off-addon/enabled"
out="$(env -i PATH="$PATH" HOME="$TMP/home" AGENTBRAIN_HOME="$B" AGENTBRAIN_VAULT="$V" ADDONS_STATE="$TMP/state" bash "$BIN" list 2>&1)"
printf '%s\n' "$out" | grep -qE '^  /off-addon +addon +enabled' && ok "ADDONS_STATE is honoured" || bad "ADDONS_STATE ignored"

# --json: the same records, stable keys, one parse.
skill "$B/system/skills/old" old "description: Old one." "deprecated:" "  reason: renamed" "  replaced_by: alpha"
json="$(run list --json)"; rc=$?
[ "$rc" = 0 ] && ok "list --json exits 0" || bad "list --json rc=$rc: $json"
check="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
keys = {"name", "source", "state", "kind", "description", "deprecated", "replaced_by"}
by = {s["name"]: s for s in d["skills"]}
errs = []
if d.get("schema") != 1: errs.append("schema")
if any(set(s) != keys for s in d["skills"]): errs.append("keys")
if sorted(by) != ["alpha", "beta", "mine", "off-addon", "old", "on-addon"]: errs.append("names %s" % sorted(by))
if by.get("on-addon", {}).get("state") != "enabled" or by["on-addon"].get("kind") != "adapter": errs.append("on-addon")
if by.get("off-addon", {}).get("state") != "available": errs.append("off-addon")
if by.get("alpha", {}).get("kind") is not None or by["alpha"].get("state") != "installed": errs.append("alpha")
if by.get("beta", {}).get("description") != "Beta folds over two lines.": errs.append("beta desc")
if by.get("mine", {}).get("source") != "local": errs.append("mine")
if by.get("old", {}).get("deprecated") is not True or by["old"].get("replaced_by") != "alpha": errs.append("old")
print(" ".join(errs) or "ok")
' 2>&1)"
[ "$check" = ok ] && ok "json fields and values" || bad "json: $check"
run list --bogus >/dev/null 2>&1 && bad "unknown list flag accepted" || ok "unknown list flag refused"

# The docs describe what the CLI does: --json in the usage and in both docs, the
# doctor check in both docs, and the thin index says where the full list lives.
DOCS="${SKILLS_DOCS:-$HERE}"
run help | grep -q 'list --json' && ok "usage names list --json" || bad "usage lacks list --json"
for f in SKILL.md README.md; do
	grep -q 'list --json' "$DOCS/$f" && grep -q 'check-skills-catalogue.sh' "$DOCS/$f" \
		&& ok "$f documents --json and the catalogue check" || bad "$f lacks --json or check-skills-catalogue.sh"
done
grep -q 'skills/bin/skills list' "$DOCS/../../skills.md" \
	&& ok "system/skills.md says where the full catalogue lives" || bad "system/skills.md does not point at skills list"

echo "skills test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
