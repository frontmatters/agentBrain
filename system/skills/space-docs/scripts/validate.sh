#!/usr/bin/env bash
# validate.sh — self-containment / boundary check for a space's documentation.
# A "space" is a project's shareable doc set (its own repo/folder). Self-contained
# means: nothing points OUTSIDE that boundary — no machine-local paths, no private
# notes/vault, no links that leave the bundle (dead, absolute, or ../-escaping to
# a sibling repo). In-scope infra (the project's own hosts) is allowed but flagged.
#
# Usage: validate.sh <docs-dir> [deny-list-file]
#   deny-list-file: optional; off-space terms (other clients, unrelated projects)
#   to reject — keep it local so those names never enter the shared repo.
# Exit 0 = self-contained, 1 = boundary/privacy/relevance leak(s), 2 = usage error.
set -u

dir="${1:-}"
[ -z "$dir" ] && { echo "usage: validate.sh <docs-dir>" >&2; exit 2; }
[ -d "$dir" ] || { echo "FAIL not a directory: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"   # absolute root of the boundary

failed=0
err()  { echo "FAIL $1"; failed=1; }
warn() { echo "WARN $1"; }

# pure-bash path normalisation (collapse . and ..; no filesystem access)
normpath() {
  local p="$1" seg res=""; local -a out=()
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ''|.) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset 'out[$((${#out[@]}-1))]' ;;
      *) out+=("$seg") ;;
    esac
  done
  res="$(IFS=/; echo "${out[*]-}")"
  [[ "$p" == /* ]] && res="/$res"
  printf '%s' "$res"
}

mapfile -d '' MDS < <(find "$dir" -type f -name '*.md' -not -path '*/.git/*' -print0)
[ "${#MDS[@]}" -eq 0 ] && { echo "FAIL no .md files in: $dir" >&2; exit 1; }

# --- 1) machine-local absolute paths (a hard leak) --------------------------
hits="$(grep -rnE '/(Users|home|root)/[A-Za-z0-9._-]+' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && err "machine-local path(s) — rewrite portable (\$HOME, ~, or relative):"$'\n'"$hits"

# --- 2) private / vault references (a hard leak) ----------------------------
hits="$(grep -rniE 'agentbrain|/\.agentbrain|/vault/|private[ _-]?notes' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && err "private/vault reference(s) — must not appear in shareable docs:"$'\n'"$hits"

# --- 3) links that leave the boundary (dead, absolute, or ../-escaping) ------
: > "/tmp/space-docs-links.$$"
for md in "${MDS[@]}"; do
  base="$(dirname "$md")"
  while IFS= read -r tgt; do
    case "$tgt" in http://*|https://*|mailto:*|\#*|"") continue ;; esac
    file="${tgt%%#*}"; [ -z "$file" ] && continue
    if [[ "$file" == /* ]]; then
      echo "  ABSLINK    $md -> $tgt  (absolute path — not portable)" >> "/tmp/space-docs-links.$$"; continue
    fi
    full="$(normpath "$base/$file")"
    case "$full" in
      "$dir"/*|"$dir") : ;;                                  # inside the boundary
      *) echo "  OUTLINK    $md -> $tgt  (resolves OUTSIDE the space: $full)" >> "/tmp/space-docs-links.$$"; continue ;;
    esac
    [ -e "$full" ] || echo "  DEADLINK   $md -> $tgt  (target not in the bundle)" >> "/tmp/space-docs-links.$$"
  done < <(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done
if [ -s "/tmp/space-docs-links.$$" ]; then
  err "link(s) leaving the boundary — bring the target IN, or make it a plain textual pointer:"$'\n'"$(cat "/tmp/space-docs-links.$$")"
fi
rm -f "/tmp/space-docs-links.$$"

# --- 4) in-scope infra: internal hosts / private IPs (WARN, not a fail) ------
hits="$(grep -rnoE '([a-z0-9-]+\.local|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && warn "internal host/IP (in-scope infra — fine, but confirm it belongs to the space):"$'\n'"$hits"

# --- 5) a README must exist (the entry point) -------------------------------
[ -f "$dir/README.md" ] || err "no README.md at the docs root (the entry point)."

# --- 6) privacy: hard secret material — never in shareable docs (FAIL) ------
hits="$(grep -rnE 'BEGIN( RSA| EC| OPENSSH| PGP| DSA)? PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && err "secret material (private key / token) — never in shareable docs:"$'\n'"$hits"

# --- 7) privacy: only space-relevant info — review these (WARN) -------------
hits="$(grep -rniE '(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]+[^ <|]{4,}' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && warn "credential-like value(s) — ok only as intentional dev/test creds, else redact to an env-var name:"$'\n'"$hits"
hits="$(grep -rnoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${MDS[@]}" 2>/dev/null || true)"
[ -n "$hits" ] && warn "email address(es) — confirm they are space-relevant, not personal PII:"$'\n'"$hits"

# --- 8) relevance: nothing off-space — other clients / unrelated (FAIL) -----
# Deny-list of terms that must NOT appear (other client names, unrelated project
# codenames, off-topic tags). Source: arg $2, or a `.space-deny` file at the docs
# root. Keep it LOCAL (pass via $2, or git-ignore `.space-deny`) so the sensitive
# names never land in the shared repo. One term (regex) per line; '#' = comment.
denyfile="${2:-}"
[ -z "$denyfile" ] && [ -f "$dir/.space-deny" ] && denyfile="$dir/.space-deny"
if [ -n "$denyfile" ] && [ -f "$denyfile" ]; then
  while IFS= read -r term || [ -n "$term" ]; do
    case "$term" in ''|\#*) continue ;; esac
    hits="$(grep -rniE -- "$term" "${MDS[@]}" 2>/dev/null || true)"
    [ -n "$hits" ] && err "off-space reference matching '/$term/i' (not required for this space):"$'\n'"$hits"
  done < "$denyfile"
fi

# --- 9) every folder documents itself — a README per subfolder (FAIL) -------
: > "/tmp/space-docs-nordm.$$"
while IFS= read -r sub; do
  [ "$sub" = "$dir" ] && continue
  case "$sub" in */.git|*/.git/*) continue ;; esac
  [ -f "$sub/README.md" ] || echo "  ${sub#"$dir"/}" >> "/tmp/space-docs-nordm.$$"
done < <(find "$dir" -type d -not -path '*/.git*')
if [ -s "/tmp/space-docs-nordm.$$" ]; then
  err "subfolder(s) without a README.md (every folder documents itself):"$'\n'"$(cat "/tmp/space-docs-nordm.$$")"
fi
rm -f "/tmp/space-docs-nordm.$$"

if [ "$failed" -eq 0 ]; then
  echo "PASS self-contained: $dir  (${#MDS[@]} docs)"
  exit 0
fi
exit 1
