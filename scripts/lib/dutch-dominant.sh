#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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

# Stopword lists come from the shared locale config (single source of truth with
# the explainer index) — add/adjust a locale in system|local/explainers/locales.json,
# not here. Falls back to the built-in set if the config is missing.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_readpat() {
	python3 - "$ROOT" <<'PY' 2>/dev/null
import json, sys, pathlib
root = sys.argv[1]; d = {}
for p in (pathlib.Path(root, "system/explainers/locales.json"),
          pathlib.Path(root, "local/explainers/locales.json")):
    if p.exists():
        try:
            for k, v in json.load(open(p)).items():
                if isinstance(v, list): d[k] = v
        except Exception: pass
print("|".join(d.get("nl", [])) + "\t" + "|".join(d.get("en", [])))
PY
}
IFS=$'\t' read -r NL EN < <(_readpat)
[ -n "${NL:-}" ] || NL='het|een|niet|wordt|zijn|naar|maar|ook|geen|deze|voor|met|je|dit'
[ -n "${EN:-}" ] || EN='the|and|with|this|that|are|you|from|when|have'

nl="$(grep -oiwE "($NL)" "$f" 2>/dev/null | wc -l | tr -d ' ')"
en="$(grep -oiwE "($EN)" "$f" 2>/dev/null | wc -l | tr -d ' ')"

[ "${nl:-0}" -gt "${en:-0}" ] && [ "${nl:-0}" -ge 8 ]
