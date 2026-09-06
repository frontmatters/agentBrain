#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lib/grandfather.sh — reusable phase-in ("grandfather clause") primitive for agentBrain checks.
#
# PROBLEM. A new quality/content rule applied retroactively to the whole vault
# fails on the entire pre-existing corpus. That blocks commits for work unrelated
# to the rule and forces an impractical mass retrofit of hundreds of old notes.
#
# METHOD. The grandfather clause phases a rule in by the note date:
#   - a note with `date:` >= the rule cutover  -> ENFORCE (born under the rule)
#   - a note with `date:` <  the cutover        -> WARN    (pre-existing, visible debt, not blocked)
#   - a note without `date:`                    -> EXEMPT  (cannot be placed in time, skip conservatively)
# So a rule is strict going forward with near-zero forced retro work. Retrofit is
# opportunistic (the WARN nudges you), never a hard gate on old notes.
#
# REUSE. A check sources this lib and calls `gf_verdict` per item. Active cutovers
# are listed centrally in system/ratchets.md; a check pins its own cutover constant
# that points there. Any future improvement gets the same phased-in rollout for free.
#
# API:
#   gf_note_date <file>            echo the frontmatter `date:` (YYYY-MM-DD) or "".
#   gf_is_after  <date> <cutover>  exit 0 if date >= cutover, else 1. Empty date -> 1.
#   gf_verdict   <file> <cutover>  echo enforce | warn | exempt (see METHOD above).
#
# Dates are ISO (YYYY-MM-DD), so a lexical compare is chronologically correct.

# Read the first frontmatter `date:` line, strip quotes/spaces, keep YYYY-MM-DD.
gf_note_date() {
	awk -F'date:' '
		/^date:/ { v=$2; gsub(/["'"'"' ]/,"",v); print substr(v,1,10); exit }
	' "$1" 2>/dev/null
}

# 0 (true) if $1 (date) >= $2 (cutover). Empty/invalid date counts as "not after".
gf_is_after() {
	[ -n "$1" ] || return 1
	# lexical on YYYY-MM-DD == chronological
	[ "$1" \< "$2" ] && return 1
	return 0
}

# enforce | warn | exempt
gf_verdict() {
	local d
	d="$(gf_note_date "$1")"
	if [ -z "$d" ]; then
		echo exempt
		return
	fi
	if gf_is_after "$d" "$2"; then
		echo enforce
	else
		echo warn
	fi
}

# Look up a rule field from the machine-readable registry (system/ratchets.tsv).
# gf_registry_field <rule-id> <col> <registry-file>  (col: 2=cutover, 3=scope-types, ...)
gf_registry_field() {
	awk -F'\t' -v r="$1" -v c="$2" '!/^#/ && $1==r { print $c; exit }' "$3" 2>/dev/null
}

# Convenience: the cutover date for a rule. Keeps the value out of the check.
gf_cutover() { gf_registry_field "$1" 2 "$2"; }
