#!/usr/bin/env bash
# dev-registry scan — MECHANISM (shared, lives in system/references/).
#
# Inventarises every dev checkout under the configured ROOTS (plus every space
# code-root) and regenerates the registry table. Path-agnostic and shareable: it
# holds NO personal paths. Your data lives NEXT TO it, in the private mirror:
#     local/references/dev-registry.roots        (your search roots — gitignored)
#     local/references/dev-registry.overrides    (manual herkomst/canonical fixes)
#     local/references/dev-registry.md           (generated output)
# A committed template ships as  system/references/dev-registry.roots.example .
#
# Spaces integration: reads local/.space-map.json (built by scripts/build-space-map.sh
# from the space paspoorts). Every checkout under a space's code-root is tagged with
# its space; the space's `canonical` code-root is marked ✓ and its other code-roots
# ⛔ decoy. So "which checkout is the real one for this client?" is a space-owned fact.
#
# Config precedence (data → mechanism):
#     $DEV_ROOTS (colon-separated) > $DEV_DIR (single, back-compat)
#       > local/references/dev-registry.roots > baked-in default (~/Developer)
#
# Columns: Naam · Herkomst · Space · Type · Wat · Canoniek? · agentBrain
# Refresh:  bash "$AGENTBRAIN_DIR"/system/references/dev-registry.scan.sh
set -euo pipefail

# --- path resolution (env-first, never hardcode a personal path) -----------
AB="${AGENTBRAIN_DIR:-$HOME/agentBrain}"
ROOTS_FILE="${ROOTS_FILE:-$AB/local/references/dev-registry.roots}"
OUT="${OUT_FILE:-$AB/local/references/dev-registry.md}"
OVERRIDES="${OVERRIDES_FILE:-$AB/local/references/dev-registry.overrides}"
SPACE_MAP="${SPACE_MAP:-$AB/local/.space-map.json}"
OWNERS_FILE="${OWNERS_FILE:-$AB/local/references/dev-registry.owners}"
BRAIN_LOCAL="$AB/local"
# Owner-identity patterns (YOUR git orgs / author names) → a checkout is "eigen".
# These are PERSONAL data, so they live in private config, never hardcoded here.
# Precedence: $DEV_OWN_RE > local/references/dev-registry.owners (one pattern/line, joined
# with |) > empty. Empty → nothing is "eigen" by remote; copy dev-registry.owners.example.
OWN_RE="${DEV_OWN_RE:-}"
if [ -z "$OWN_RE" ] && [ -f "$OWNERS_FILE" ]; then
  OWN_RE=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$OWNERS_FILE" | paste -sd'|' -)
fi

trim(){ local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# --- resolve ROOTS (data lives in local/, not here) ------------------------
declare -a ROOTS=()
if [ -n "${DEV_ROOTS:-}" ]; then
  IFS=':' read -r -a ROOTS <<< "$DEV_ROOTS"
elif [ -n "${DEV_DIR:-}" ]; then
  ROOTS=("$DEV_DIR")                                   # back-compat single root
elif [ -f "$ROOTS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line="$(trim "$line")"; [ -z "$line" ] && continue
    line="${line/#\~/$HOME}"; line="${line//\$HOME/$HOME}"
    ROOTS+=("$line")
  done < "$ROOTS_FILE"
fi
[ ${#ROOTS[@]} -eq 0 ] && ROOTS=("$HOME/Developer")    # baked-in default

# --- spaces: refresh + consume the space-map (by-code-root + canonical) -----
# Best-effort refresh so the registry reflects the current paspoorts (idempotent).
[ -x "$AB/scripts/build-space-map.sh" ] && bash "$AB/scripts/build-space-map.sh" >/dev/null 2>&1 || true
declare -A SPACE_OF CANON_OF
declare -a SPACE_ROOTS=()
if [ -f "$SPACE_MAP" ]; then
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      CR) rpa=$(cd "$a" 2>/dev/null && pwd -P) || rpa="$a"; SPACE_OF["$rpa"]="$b"; SPACE_ROOTS+=("$rpa");;
      CA) rpb=$(cd "$b" 2>/dev/null && pwd -P) || rpb="$b"; CANON_OF["$a"]="$rpb";;
    esac
  done < <(python3 - "$SPACE_MAP" <<'PY'
import json,sys
try: m=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for path,slug in (m.get("by-code-root") or {}).items(): print(f"CR\t{path}\t{slug}")
for slug,path in (m.get("canonical") or {}).items():   print(f"CA\t{slug}\t{path}")
PY
)
fi

# --- manual overrides: "naam herkomst [status]" (status = canonical|decoy) --
override_herk(){   [ -f "$OVERRIDES" ] && awk -v n="$1" '!/^#/ && $1==n{print $2; exit}' "$OVERRIDES"; }
override_status(){ [ -f "$OVERRIDES" ] && awk -v n="$1" '!/^#/ && $1==n{print $3; exit}' "$OVERRIDES"; }

esc(){ printf '%s' "$1" | tr '|' '/' | tr -d '\r' | cut -c1-90; }

is_eigen_pkg(){
  [ -n "$OWN_RE" ] || return 1
  [ -f "$1/package.json" ] && node -e 'const p=require(process.argv[1]);const a=typeof p.author==="string"?p.author:((p.author&&p.author.name)||"");process.exit(new RegExp(process.argv[2],"i").test((p.name||"")+" "+a)?0:1)' "$1/package.json" "$OWN_RE" 2>/dev/null
}
classify_herkomst(){
  local d="$1" url
  case "$d" in */_work/*|*/_work) echo "klant"; return;; esac
  if [ -d "$d/.git" ]; then
    url=$(git -C "$d" remote get-url origin 2>/dev/null || true)
    if [ -n "$url" ]; then
      if [ -n "$OWN_RE" ] && printf '%s' "$url" | grep -qiE "$OWN_RE"; then echo "eigen"; else echo "extern"; fi
      return
    fi
  fi
  if [ -d "$d/.git" ]; then
    ae=$(git -C "$d" log -1 --format=%ae 2>/dev/null || true)
    if [ -n "$OWN_RE" ] && printf '%s' "$ae" | grep -qiE "$OWN_RE"; then echo "eigen"; return; fi
    [ -n "$ae" ] && { echo "extern"; return; }
  fi
  if is_eigen_pkg "$d"; then echo "eigen"; else echo "lokaal?"; fi
}

detect_type(){
  local d="$1"
  if [ -d "$d/bin" ] || { [ -f "$d/package.json" ] && grep -q '"bin"' "$d/package.json" 2>/dev/null; }; then echo "cli"
  elif [ -f "$d/package.json" ] && grep -qE '"(react|vite|next|@tauri|electron|lit)"' "$d/package.json" 2>/dev/null; then echo "app"
  elif [ -f "$d/package.json" ]; then echo "lib/pkg"
  elif [ -f "$d/Cargo.toml" ]; then echo "rust"
  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/requirements.txt" ]; then echo "python"
  else echo "overig"; fi
}

describe(){
  local d="$1" desc=""
  if [ -f "$d/package.json" ]; then
    desc=$(node -e 'try{process.stdout.write((require(process.argv[1]).description||"").toString())}catch(e){}' "$d/package.json" 2>/dev/null || true)
  fi
  if [ -z "$desc" ] && [ -f "$d/README.md" ]; then
    desc=$(grep -vE '^\s*($|#|!\[|<)' "$d/README.md" 2>/dev/null | head -1 | sed 's/^[*>_-]*//; s/`//g')
  fi
  [ -z "$desc" ] && desc="-"
  esc "$desc"
}

ab_link(){
  local n="$1" hit cand
  for cand in "projects/$n/index" "projects/$n/$n" "stubs/$n" "references/tools/$n" "integrations/$n" "references/$n"; do
    [ -f "$BRAIN_LOCAL/$cand.md" ] && { printf '[[%s]]' "$cand"; return; }
  done
  hit=$(grep -rIlw -i -- "$n" \
        "$BRAIN_LOCAL"/projects "$BRAIN_LOCAL"/references "$BRAIN_LOCAL"/learnings \
        "$BRAIN_LOCAL"/integrations "$BRAIN_LOCAL"/specs "$BRAIN_LOCAL"/troubleshooting \
        "$BRAIN_LOCAL"/stubs "$BRAIN_LOCAL"/backlog 2>/dev/null \
        | grep -vE '/dev-registry\.md' | head -1 || true)
  if [ -n "$hit" ]; then
    local rel="${hit#$BRAIN_LOCAL/}"; rel="${rel%.md}"
    printf '[[%s]]' "$rel"
  else printf '—'; fi
}

# --- pass 1: collect checkouts (dedup by realpath, count origins) -----------
declare -A SEEN ORIGIN_COUNT
declare -a NAMES DIRS ORIGINS
add_checkout(){ # $1 = realpath dir
  local d="$1" n origin
  [ -d "$d" ] || return 0
  [ -n "${SEEN[$d]:-}" ] && return 0
  SEEN[$d]=1
  n=$(basename "$d")
  origin=$(git -C "$d" remote get-url origin 2>/dev/null || true)
  [ -n "$origin" ] && ORIGIN_COUNT["$origin"]=$(( ${ORIGIN_COUNT["$origin"]:-0} + 1 ))
  NAMES+=("$n"); DIRS+=("$d"); ORIGINS+=("$origin")
}
for DEV in "${ROOTS[@]}"; do
  [ -d "$DEV" ] || continue
  for d in "$DEV"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    case "$n" in _*|.*|-*|\#*|\[*|20[0-9][0-9]-[0-9]*|*backup*|*downloads*|*-tmp-*|tmp|test|docs|Projects|references|parked|worktrees|mkdir-today|builds|node_modules) continue;; esac
    rp=$(cd "$d" 2>/dev/null && pwd -P) || continue
    add_checkout "$rp"
  done
done
# space code-roots (explicit client checkouts, possibly outside the roots)
for d in "${SPACE_ROOTS[@]}"; do add_checkout "$d"; done

# --- pass 2: build rows -----------------------------------------------------
declare -a ROWS
count_eigen=0; count_extern=0; count_klant=0; count_lokaal=0; total=0; count_decoy=0; count_spaced=0
for i in "${!NAMES[@]}"; do
  n="${NAMES[$i]}"; d="${DIRS[$i]}"; origin="${ORIGINS[$i]}"
  space="${SPACE_OF[$d]:-}"
  herk=$(override_herk "$n"); [ -z "$herk" ] && herk=$(classify_herkomst "$d")
  typ=$(detect_type "$d"); wat=$(describe "$d"); ab=$(ab_link "$n")
  if [ -n "$space" ] && [ -n "${CANON_OF[$space]:-}" ]; then
    if [ "$d" = "${CANON_OF[$space]}" ]; then canon="✓"; else canon="⛔ decoy"; count_decoy=$((count_decoy+1)); fi
  else
    st=$(override_status "$n")
    case "$st" in
      canonical) canon="✓";;
      decoy)     canon="⛔ decoy"; count_decoy=$((count_decoy+1));;
      *) if [ -n "$origin" ] && [ "${ORIGIN_COUNT["$origin"]:-0}" -gt 1 ]; then canon="⚠ dup"; else canon=""; fi;;
    esac
  fi
  [ -n "$space" ] && count_spaced=$((count_spaced+1))
  ROWS+=("| $n | $herk | ${space:-—} | $typ | $wat | $canon | $ab |")
  total=$((total+1))
  case "$herk" in eigen)count_eigen=$((count_eigen+1));; extern)count_extern=$((count_extern+1));; klant)count_klant=$((count_klant+1));; lokaal?)count_lokaal=$((count_lokaal+1));; esac
done

TS=$(date +%Y-%m-%d)
ROOTS_STR=$(printf '%s, ' "${ROOTS[@]}"); ROOTS_STR="${ROOTS_STR%, }"
BODY=$(mktemp)
{
  echo "_Laatst gescand: $TS · $total mappen (eigen $count_eigen · extern $count_extern · klant $count_klant · lokaal/onbekend $count_lokaal · spaces $count_spaced · decoys $count_decoy). Roots: ${ROOTS_STR}. Herkomst uit git-remote; Space/canoniek uit local/.space-map.json (paspoorten); \`lokaal?\` = geen remote._"
  echo
  echo "| Naam | Herkomst | Space | Type | Wat | Canoniek? | agentBrain |"
  echo "|---|---|---|---|---|---|---|"
  printf '%s\n' "${ROWS[@]}" | sort -f
} > "$BODY"

if [ ! -f "$OUT" ]; then echo "FOUT: $OUT bestaat niet — maak 'm eerst met new-note.sh" >&2; exit 1; fi
awk -v body="$BODY" '
  /<!-- BEGIN AUTO -->/ {print; while((getline l < body)>0) print l; skip=1; next}
  /<!-- END AUTO -->/   {skip=0}
  !skip {print}
' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
rm -f "$BODY"
echo "dev-registry bijgewerkt: $total mappen ($count_spaced spaced, $count_decoy decoys) → $OUT"
