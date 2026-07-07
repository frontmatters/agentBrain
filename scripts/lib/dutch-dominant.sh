#!/usr/bin/env bash
# dutch-dominant.sh — exit 0 if the given markdown file is Dutch-dominant, else 1.
#
# Canonical Dutch-detection for the English-only policy gates: the public layer
# (everything outside local/) must be English. Used by doctor's
# check-english-sources.sh and by the promote skill's pre-move gate, so both
# share one heuristic and cannot drift apart.
#
# Heuristic: count unambiguous Dutch vs English stopwords (word-bounded). Dutch
# wins only if it both exceeds English AND clears a small floor — this ignores
# near-empty or code-only stubs and keeps false positives off the 98%-English
# system/ tree.
set -u

f="${1:?usage: dutch-dominant.sh <file>}"
[ -f "$f" ] || exit 1

NL='het|een|niet|wordt|zijn|naar|maar|ook|geen|deze|voor|met|je|dit'
EN='the|and|with|this|that|are|you|from|when|have'

nl="$(grep -oiwE "($NL)" "$f" 2>/dev/null | wc -l | tr -d ' ')"
en="$(grep -oiwE "($EN)" "$f" 2>/dev/null | wc -l | tr -d ' ')"

[ "${nl:-0}" -gt "${en:-0}" ] && [ "${nl:-0}" -ge 8 ]
