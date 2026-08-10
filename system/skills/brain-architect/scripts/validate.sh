#!/usr/bin/env bash
# validate.sh — deterministic form-check for /architect dossiers.
# Usage: validate.sh <dossier.md> [repo-root]
# Exit 0 = pass, 1 = findings, 2 = usage error.
# Checks FORM only (sections, evidence paths, diagrams, decision completeness);
# thinking quality is the job of --peer-review, not this script.
set -u

dossier="${1:-}"
repo_root="${2:-}"
[ -z "$dossier" ] && { echo "usage: validate.sh <dossier.md> [repo-root]" >&2; exit 2; }
[ -f "$dossier" ] || { echo "FAIL dossier not found: $dossier" >&2; exit 1; }

failed=0
err() { echo "FAIL $1"; failed=1; }

# repo root: arg 2 wins, else frontmatter 'repo:' line
if [ -z "$repo_root" ]; then
  repo_root="$(awk 'f && /^---$/{exit} /^---$/{f=1;next} f && sub(/^repo:[[:space:]]*/,""){print;exit}' "$dossier")"
fi
# strip surrounding quotes (YAML-quoted values: "path" or 'path')
repo_root="${repo_root%\"}"; repo_root="${repo_root#\"}"
repo_root="${repo_root%\'}"; repo_root="${repo_root#\'}"
# strip trailing whitespace
repo_root="$(printf '%s' "$repo_root" | sed 's/[[:space:]]*$//')"
# expand leading tilde
case "$repo_root" in "~"*) repo_root="$HOME${repo_root#\~}";; esac

# fenced code blocks must not affect structural checks (sections, lenses,
# placeholders, decisions, thin-sections) — a dossier quotes code as evidence
stripped="$(awk '/^[[:space:]]*```/{f=!f; next} !f' "$dossier")"

# 1 — required section anchors (language-neutral tokens, never translated)
for h in "## Recon" "## Building Blocks" "## Constraints" "## Decisions" "## Open Questions"; do
  printf '%s\n' "$stripped" | grep -q "^$h" || err "missing section: $h"
done

# 2 — the six constraint lenses
for lens in "Egress" "Data & Storage" "Secrets" "Identity & Access" "Compliance" "Operations"; do
  printf '%s\n' "$stripped" | grep -q "^### $lens" || err "missing constraint lens: ### $lens"
done

# 3 — no placeholders
ph="$(printf '%s\n' "$stripped" | grep -nE 'TBD|TODO' || true)"
[ -n "$ph" ] && err "placeholders found:
$ph"

# 4 — at least two mermaid diagrams
mcount="$(grep -c '^[[:space:]]*```mermaid' "$dossier" || true)"
[ "$mcount" -ge 2 ] || err "need >=2 mermaid diagrams, found $mcount"

# 5 — evidence: at least 3 markers; every backticked path must exist.
#     Path form:  evidence: `relative/or/abs/path[:line]`
#     Non-path evidence (command output, prose) is allowed and not path-checked.
ev_total="$(grep -c 'evidence:' "$dossier" || true)"
[ "$ev_total" -ge 3 ] || err "need >=3 evidence: markers, found $ev_total"
if [ -z "$repo_root" ]; then
  rel="$(sed -n 's/.*evidence:[^`]*`\([^`]*\)`.*/\1/p' "$dossier" | grep -v '^[/~]' || true)"
  [ -n "$rel" ] && err "no repo-root: pass it as arg 2 or add 'repo:' to the frontmatter"
fi
bad_ev="$(sed -n 's/.*evidence:[^`]*`\([^`]*\)`.*/\1/p' "$dossier" | while IFS= read -r ref; do
  p="$ref"
  case "$p" in *:[0-9]*) p="${p%:*}";; esac
  case "$p" in
    /*) t="$p" ;;
    "~"*) t="$HOME${p#\~}" ;;
    *) t="$repo_root/$p" ;;
  esac
  [ -e "$t" ] || printf '%s\n' "$ref"
done)"
[ -n "$bad_ev" ] && err "evidence paths not found (repo-root='$repo_root'):
$bad_ev"

# 6 — decision records: >=1 record; each needs >=2 options, >=1 abort-condition,
#     and >=1 Recommendation
dec_count="$(printf '%s\n' "$stripped" | grep -c '^### Decision:' || true)"
[ "$dec_count" -ge 1 ] || err "no decision records (### Decision:) found"
baddec="$(printf '%s\n' "$stripped" | awk '
  function flush() { if (name != "" && (opts < 2 || aborts < 1 || recs < 1)) printf "%s (options=%d, abort-conditions=%d, recommendations=%d)\n", name, opts, aborts, recs }
  /^### Decision:/ { flush(); name=$0; opts=0; aborts=0; recs=0; next }
  /^## / { flush(); name="" }
  name != "" && /\*\*Option / { opts++ }
  name != "" && /^abort-condition:/ { aborts++ }
  name != "" && /\*\*Recommendation:/ { recs++ }
  END { flush() }
')"
[ -n "$baddec" ] && err "incomplete decision records:
$baddec"

# 7 — no near-empty top-level sections (>=2 non-empty lines before the next ##)
thin="$(printf '%s\n' "$stripped" | awk '
  /^## /{ if (sec != "" && n < 2) print sec; sec=$0; n=0; next }
  sec != "" && NF > 0 { n++ }
  END { if (sec != "" && n < 2) print sec }
')"
[ -n "$thin" ] && err "sections with fewer than 2 content lines:
$thin"

# 8 — at least one ⚠ Open marker (unknowns must be explicit; the Open
#     Questions header carries one when the template is followed)
printf '%s\n' "$stripped" | grep -q '⚠ Open' || err "no '⚠ Open' marker found — unknowns must be explicit (or state none in Open Questions)"

if [ "$failed" -eq 0 ]; then
  echo "OK dossier passes all form checks"
else
  exit 1
fi
