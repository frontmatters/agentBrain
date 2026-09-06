#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-decisions.sh — Validate ADR decision-records under
# local/projects/*/decisions.md (+ local/spaces/*/projects/*/decisions.md).
#
# The discipline is lifted from DeepSeek Harness's decision-record gate: a decision
# recorded without what it beat invites re-litigation. Per ADR block
# (`## ADR-NNN: Title (date)`, see templates/project-decisions.md) this enforces:
#
#   FAIL  - Status missing or not in {proposed, accepted, deprecated, superseded}
#   FAIL  - missing required bullet: Decision or Consequences
#   WARN  - an *accepted* ADR without a non-empty Alternatives field
#           (the field that stops you re-litigating a settled decision)
#   WARN  - proposal-language (TBD / to be decided / we should / ???) in an
#           accepted ADR — a "shipped" record should not read like a proposal
#
# Alternatives is WARN not FAIL by design: it is a warn-first rollout so an existing
# vault with gaps does not break `doctor` on day one. Promote to FAIL once clean.
#
# Scans ${AGENTBRAIN_DIR:-<repo-root>}/local so it is testable against a tmpdir
# fixture. No-op if no decision-records exist.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
BASE="${AGENTBRAIN_DIR:-$ROOT_DIR}"

shopt -s nullglob
files=("$BASE"/vault/projects/*/decisions.md "$BASE"/vault/spaces/*/projects/*/decisions.md)
if [ ${#files[@]} -eq 0 ]; then
	echo "check-decisions: no decision-records (nothing to validate)"
	exit 0
fi

# ── Per-file awk: split into ADR blocks, validate each, emit FAIL/WARN lines ──
read -r -d '' ADR_FILTER <<'AWK' || true
function bulletval(l,   v) {
	v = l
	sub(/^.*\*\*[A-Za-z]+\*\*[: ]*/, "", v)   # strip up to "**Field**: "
	gsub(/^[ \t]+|[ \t]+$/, "", v)
	return v
}
function flush(   n, lines, i, l, status, hasDec, hasCons, hasAlt, altEmpty, altIdx, j, t, low) {
	if (adr == "") return
	n = split(buf, lines, "\n")
	status = "__none__"; hasDec = 0; hasCons = 0; hasAlt = 0; altEmpty = 0; altIdx = 0
	for (i = 1; i <= n; i++) {
		l = lines[i]
		if (l ~ /\*\*Status\*\*/)            { status = bulletval(l) }
		else if (l ~ /\*\*Decision\*\*/)     { hasDec = 1 }
		else if (l ~ /\*\*Consequences\*\*/) { hasCons = 1 }
		else if (l ~ /\*\*Alternatives\*\*/) { hasAlt = 1; altIdx = i; if (bulletval(l) == "") altEmpty = 1 }
	}
	# Multi-line Alternatives: an empty inline header counts as present when
	# sub-bullets follow it (before the next `- **Field**` bullet / ADR heading).
	if (hasAlt && altEmpty && altIdx > 0) {
		for (j = altIdx + 1; j <= n; j++) {
			if (lines[j] ~ /^-[ \t]+\*\*/ || lines[j] ~ /^##[ \t]/) break
			t = lines[j]; gsub(/[ \t]/, "", t)
			if (t != "") { altEmpty = 0; break }
		}
	}
	# Match the enum on the leading word so a qualifier is tolerated, e.g.
	# "accepted (supersedes ADR-001)" is still `accepted`.
	statusword = tolower(status); sub(/[^a-z].*$/, "", statusword)
	if (status == "__none__")
		print "FAIL " F " " adr ": missing Status"
	else if (statusword !~ /^(proposed|accepted|deprecated|superseded)$/)
		print "FAIL " F " " adr ": invalid Status '" status "'"
	if (!hasDec)  print "FAIL " F " " adr ": missing Decision"
	if (!hasCons) print "FAIL " F " " adr ": missing Consequences"
	if (statusword == "accepted") {
		if (!hasAlt || altEmpty)
			print "WARN " F " " adr ": accepted ADR missing Alternatives (records what it beat)"
		low = tolower(buf)
		if (low ~ /tbd|to be decided|we should|\?\?\?/)
			print "WARN " F " " adr ": proposal-language in accepted ADR"
	}
}
/^##[ \t]+ADR-/ {
	flush()
	adr = $0; sub(/^##[ \t]+/, "", adr); sub(/:.*/, "", adr)   # -> "ADR-001"
	buf = ""; inblock = 1
	next
}
inblock { buf = buf "\n" $0 }
END { flush() }
AWK

report=""
for f in "${files[@]}"; do
	rel="${f#"$BASE"/}"
	out="$(awk -v F="$rel" "$ADR_FILTER" "$f" 2>/dev/null || true)"
	[ -n "$out" ] && report+="$out"$'\n'
done

fails=0
warns=0
if [ -n "${report//[$'\n']/}" ]; then
	fails="$(printf '%s\n' "$report" | grep -c '^FAIL ' || true)"
	warns="$(printf '%s\n' "$report" | grep -c '^WARN ' || true)"
	printf '%s\n' "$report" | sed '/^$/d' >&2
fi

if [ "$fails" -gt 0 ]; then
	echo "check-decisions: $fails invalid ADR(s), $warns warning(s)" >&2
	exit 1
fi

echo "check-decisions: OK ($warns warning(s))"
