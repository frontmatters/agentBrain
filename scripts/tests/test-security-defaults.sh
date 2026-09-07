#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-security-defaults.sh — mechanical assertions for the OWASP LLM Top 10
# rollout (spec: local/specs/2026-08-31-owasp-llm-compliance-rollout.md).
# Grows one block per slice; every assertion is greppable, no LLM in the loop.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"; cd "$ROOT_DIR" || exit 1
fails=0
# Registry addons (everything outside scripts/lib/essential-addons.txt) are absent
# from a release archive and a fresh install: an assertion on their files is a
# skip there, not a failure. Measured: two red slices in the release gate's sandbox.
addon_absent() { # addon_absent <file> -> 0 when the file sits under a registry addon that is not here
	case "$1" in
		system/addons/*/*) local id="${1#system/addons/}"; id="${id%%/*}"; [ ! -d "system/addons/$id" ] ;;
		*) return 1 ;;
	esac
}
assert_contains() { # assert_contains <file> <pattern> <label>
	addon_absent "$1" && { echo "skip $3 (registry addon not present here)"; return 0; }
	if grep -qE "$2" "$1" 2>/dev/null; then echo "ok   $3"; else echo "FAIL $3 (missing '$2' in $1)" >&2; fails=$((fails+1)); fi
}
assert_not_contains() { # assert_not_contains <file> <pattern> <label>
	addon_absent "$1" && { echo "skip $3 (registry addon not present here)"; return 0; }
	if grep -qE "$2" "$1" 2>/dev/null; then echo "FAIL $3 (forbidden '$2' present in $1)" >&2; fails=$((fails+1)); else echo "ok   $3"; fi
}
assert_file_absent() { # assert_file_absent <path> <label>
	addon_absent "$1" && { echo "skip $2 (registry addon not present here)"; return 0; }
	if [ -e "$1" ]; then echo "FAIL $2 (still exists: $1)" >&2; fails=$((fails+1)); else echo "ok   $2"; fi
}

# ── slice 1: the policy note exists and carries every standing decision ──────
POLICY=system/security-policy.md
if [ -f "$POLICY" ]; then echo "ok   policy note present"; else echo "FAIL policy note missing ($POLICY)" >&2; fails=$((fails+1)); fi
assert_contains "$POLICY" 'never instructions'            'policy: canonical norm present'
assert_contains "$POLICY" 'source: external'              'policy: marker spec present'
assert_contains "$POLICY" 'origin:'                       'policy: origin field present'
assert_contains "$POLICY" 'source-date:'                  'policy: source-date field present'
assert_contains "$POLICY" 'Data-exit rule'                'policy: cloud-exit rule present'
assert_contains "$POLICY" 'LLM07'                         'policy: LLM07 decision present'
assert_contains "$POLICY" 'LLM08'                         'policy: LLM08 decision present'
assert_contains "$POLICY" 'LLM09'                         'policy: LLM09 decision present'
assert_contains "$POLICY" 'LLM04'                         'policy: LLM04 decision present'

# ── slice 2: youtube-digest writes the marker ─────────────────────────────────
# youtube-digest is a registry addon: absent from a release archive and from a
# fresh install (slim core). The slice applies where the addon is present.
if [ -f system/addons/youtube-digest/src/sync.ts ]; then
assert_contains system/addons/youtube-digest/src/sync.ts 'source: external' 'youtube-digest: marker present'
assert_contains system/addons/youtube-digest/src/sync.ts 'origin: \$\{video.url\}' 'youtube-digest: origin field present'
assert_contains system/addons/youtube-digest/src/sync.ts 'source-date: \$\{dateFormatted\}' 'youtube-digest: source-date field present'
assert_contains system/addons/youtube-digest/src/sync.ts 'never instructions' 'youtube-digest: norm referenced'
else
	echo "skip youtube-digest: registry addon, not present here"
fi

# ── slice 3: the local-first LLM-config pattern ───────────────────────────────
LIB=system/lib/llm-config.ts
if [ -f "$LIB" ]; then echo "ok   llm-config resolver present"; else echo "FAIL llm-config resolver missing ($LIB)" >&2; fails=$((fails+1)); fi
assert_contains "$LIB" 'resolveLlmConfig'        'llm-config: resolver exported'
assert_contains "$LIB" 'probeOllama'             'llm-config: ollama fallback present'
assert_contains "$LIB" ':cloud'                  'llm-config: ollama cloud-models filtered'
[ -d system/addons/youtube-digest ] && assert_file_absent system/addons/youtube-digest/src/glm.ts 'llm-config: dead z.ai cloud client removed'
assert_contains system/security-policy.md 'user- and model-agnostic' 'policy: agnostic-pattern section present'
# ── slice 3b: the llm-config addon ───────────────────────────────────────
ADDON_MANIFEST=system/addons/llm-config/manifest.md
if [ ! -d system/addons/llm-config ]; then echo "skip llm-config addon (registry addon not present here)"
elif [ -f "$ADDON_MANIFEST" ]; then echo "ok   llm-config addon manifest present"; else echo "FAIL llm-config addon manifest missing ($ADDON_MANIFEST)" >&2; fails=$((fails+1)); fi
assert_contains "$ADDON_MANIFEST" '^id: llm-config' 'llm-config addon: id registered'
assert_contains "$ADDON_MANIFEST" 'vault/config/llm.json' 'llm-config addon: user-wide layer documented'
# Shipped example configs never carry an endpoint (values live per user in local/)
for ex in system/addons/*/*.example.json; do
	[ -e "$ex" ] || continue
	assert_not_contains "$ex" '"endpoint"' "example config clean: $ex"
done

# ── slice 4: chatgpt-import writes the marker ─────────────────────────────
assert_contains system/addons/chatgpt-import/bin/chatgpt-import '"source": "external"' 'chatgpt-import: marker present'
assert_contains system/addons/chatgpt-import/bin/chatgpt-import '"origin": url' 'chatgpt-import: origin field present'
assert_contains system/addons/chatgpt-import/bin/chatgpt-import '"source-date"' 'chatgpt-import: source-date field present'
assert_contains system/addons/chatgpt-import/SKILL.md 'never instructions' 'chatgpt-import: norm referenced'

# ── slice 5: peer-review no longer defaults to cloud ─────────────────────────
assert_not_contains system/skills/peer-review/bin/peer-review 'PEER_REVIEW_DEFAULT_LLM:-ollama-cloud' 'peer-review: no shipped cloud default'
assert_contains system/skills/peer-review/bin/peer-review 'resolve_default_llm' 'peer-review: cascade resolver present'
assert_contains system/skills/peer-review/bin/peer-review 'data-exit' 'peer-review: data-exit disclosure present'
assert_contains system/skills/peer-review/SKILL.md 'cascaded config' 'peer-review: SKILL.md documents cascade'

# ── slice 6: weekly-review cloud only via config pin or --cloud ─────────────
WR=system/addons/weekly-review/bin/weekly-review
assert_not_contains "$WR" "summarizer.provider // \"ollama-cloud\"" 'weekly-review: no shipped cloud provider default'
assert_not_contains "$WR" "summarizer.model // \"gpt-oss:120b-cloud\"" 'weekly-review: no shipped cloud model default'
assert_contains "$WR" '[-][-]cloud\)' 'weekly-review: explicit --cloud flag present'
assert_contains "$WR" 'data-exit' 'weekly-review: data-exit disclosure present'
assert_contains system/addons/weekly-review/SKILL.md 'no shipped default' 'weekly-review: SKILL.md documents the new default'

# ── slice 5 (pending): peer-review no longer defaults to cloud ──────────────
# assert_not_contains system/skills/peer-review/SKILL.md 'Default backend ollama-cloud' 'peer-review: no cloud default'

# ── slice 5: weekly-review cloud only via flag (added in slice 5) ────────────

if [ "$fails" = 0 ]; then echo "test-security-defaults: ok"; else echo "test-security-defaults: $fails fail(s)" >&2; exit 1; fi
