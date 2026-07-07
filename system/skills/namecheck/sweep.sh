#!/usr/bin/env bash
# namecheck sweep.sh — sweep a product name across claimable namespaces.
# For every TAKEN resource, fetch what's behind it so the user can judge conflict.
#
# Usage:
#   bash sweep.sh <name> [<name2> <name3> ...]
#
# Output: per-name tiered report (FREE / TAKEN + one-liner description).
#
# Dependencies: bash 4+, curl, dig (bind-utils), python3, jq or python for JSON parse.
# Tested on macOS. Linux works except `dig` package name varies.

set -uo pipefail

# --- color helpers (respect NO_COLOR) ---
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  C_FREE=""; C_TAKEN=""; C_DIM=""; C_RESET=""
else
  C_FREE=$'\033[32m'; C_TAKEN=$'\033[33m'
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
fi

if [[ $# -lt 1 ]]; then
  cat >&2 <<EOF
Usage: $0 <name> [<name2> <name3> ...]

Sweeps each name across npm, GitHub, Open VSX, VS Code Marketplace, Homebrew,
common TLDs, X/Twitter, and Reddit. For TAKEN resources, prints what's behind it.

Examples:
  $0 cortexa
  $0 encephr encephix mentisio vellio
EOF
  exit 2
fi

TLD_LIST="com io dev ai app so sh run tech tools co"
GH_VARIANTS_SUFFIX="-ide -dev"   # appended as "<name><suffix>"
GH_VARIANTS_PREFIX="get use"     # produced as "<prefix><name>"

http_code() {
  curl -s -o /dev/null -w "%{http_code}" --max-time "${CURL_TIMEOUT:-8}" "$1"
}

# fetch + one-line description per registry
describe_npm() {
  local pkg="$1"
  curl -s --max-time "${CURL_TIMEOUT:-8}" "https://registry.npmjs.org/$pkg" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d: print('FREE'); sys.exit()
    latest = d.get('dist-tags', {}).get('latest', '')
    v = d.get('versions', {}).get(latest, {})
    desc = (v.get('description') or '(no description)').strip().replace('\n',' ')
    author = v.get('author', {})
    if isinstance(author, dict): author = author.get('name','?')
    homepage = v.get('homepage') or ''
    t = d.get('time', {}).get(latest, '?')[:10]
    print(f'TAKEN · {desc[:140]}')
    print(f'       author: {author} | last: {t} | {homepage}')
except Exception as e:
    print('FREE?')
" 2>/dev/null
}

describe_npm_scope() {
  local scope="$1"
  local code; code=$(http_code "https://registry.npmjs.org/@${scope}%2Fcore")
  if [[ "$code" == "404" ]]; then echo "FREE"; else echo "TAKEN (scope exists)"; fi
}

describe_github_user() {
  local u="$1"
  curl -s --max-time "${CURL_TIMEOUT:-8}" "https://api.github.com/users/$u" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'message' in d and d['message'] == 'Not Found':
        print('FREE'); sys.exit()
    name = d.get('name') or '(no name)'
    bio = (d.get('bio') or '(no bio)').strip().replace('\n',' ')[:120]
    company = d.get('company') or '?'
    blog = d.get('blog') or ''
    typ = d.get('type', '?')
    repos = d.get('public_repos', '?')
    created = (d.get('created_at') or '?')[:10]
    print(f'TAKEN · {typ} | {name} | {bio}')
    print(f'       company: {company} | repos: {repos} | since: {created} | {blog}')
except Exception:
    print('FREE?')
" 2>/dev/null
}

describe_openvsx() {
  local ns="$1"
  local code; code=$(http_code "https://open-vsx.org/api/$ns")
  if [[ "$code" == "404" ]]; then echo "FREE"; else echo "TAKEN (namespace exists)"; fi
}

describe_vscode_mkt() {
  local n="$1"
  curl -s --max-time "${CURL_TIMEOUT:-10}" "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
    -H "Content-Type: application/json" -H "Accept: application/json;api-version=3.0-preview.1" \
    -d "{\"filters\":[{\"criteria\":[{\"filterType\":10,\"value\":\"$n\"}]}],\"flags\":914}" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cnt = d['results'][0]['resultMetadata'][0]['metadataItems'][0]['count']
    exts = d['results'][0].get('extensions', [])
    if cnt == 0: print('FREE (0 hits)')
    else:
        names = [e.get('publisher',{}).get('publisherName','?') + '.' + e.get('extensionName','?') for e in exts[:3]]
        print(f'TAKEN · {cnt} hit(s); top: {names}')
except Exception:
    print('?')
" 2>/dev/null
}

describe_brew() {
  local kind="$1" name="$2" url
  if [[ "$kind" == "formula" ]]; then
    url="https://formulae.brew.sh/api/formula/$name.json"
  else
    url="https://formulae.brew.sh/api/cask/$name.json"
  fi
  local code; code=$(http_code "$url")
  if [[ "$code" == "404" ]]; then echo "FREE"; return; fi
  curl -s --max-time "${CURL_TIMEOUT:-8}" "$url" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    desc = d.get('desc') or '(no desc)'
    hp = d.get('homepage') or ''
    fn = d.get('full_name') or d.get('full_token') or '?'
    print(f'TAKEN · {fn} — {desc} | {hp}')
except Exception:
    print('TAKEN (?)')
" 2>/dev/null
}

describe_domain() {
  local d="$1"
  local ns a
  ns=$(dig +short +time=2 +tries=1 "$d" NS 2>/dev/null | head -1)
  a=$(dig +short +time=2 +tries=1 "$d" A 2>/dev/null | head -1)
  if [[ -z "$ns" && -z "$a" ]]; then echo "FREE"; return; fi
  # try to fetch <title>
  local title
  title=$(curl -sL --max-time "${CURL_TIMEOUT:-8}" "https://$d" 2>/dev/null \
    | grep -ioE "<title>[^<]+</title>" | head -1 | sed -E 's/<\/?title>//gi' | tr -s ' ')
  if [[ -z "$title" ]]; then title="(no title/response — parked?)"; fi
  echo "TAKEN · $title"
}

describe_x() {
  local handle="$1"
  local code; code=$(http_code "https://x.com/$handle")
  if [[ "$code" == "404" ]]; then echo "FREE (404)"; else echo "TAKEN (status $code — X blocks scrape, verify by signup)"; fi
}

describe_reddit() {
  local sub="$1"
  curl -sL --max-time "${CURL_TIMEOUT:-8}" "https://www.reddit.com/r/$sub/about.json" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['data']
    title = d.get('title','?')
    subs = d.get('subscribers','?')
    desc = (d.get('public_description','') or '(none)').strip().replace('\n',' ')[:100]
    print(f'TAKEN · {title} | subs: {subs} | {desc}')
except Exception:
    print('FREE?')
" 2>/dev/null
}

print_row() {
  local label="$1" status="$2"
  local marker color
  case "$status" in
    FREE*) marker="✓"; color="$C_FREE" ;;
    TAKEN*) marker="✗"; color="$C_TAKEN" ;;
    *) marker="?"; color="$C_DIM" ;;
  esac
  printf "  ${color}%-4s${C_RESET} %-22s %s\n" "$marker" "$label" "$status"
}

sweep_name() {
  local n="$1"
  echo "════════════════════════════════════════════════════════════════"
  echo "  ${C_DIM}name:${C_RESET} ${n}"
  echo "════════════════════════════════════════════════════════════════"
  echo
  echo "  ${C_DIM}─── code registries ───${C_RESET}"
  print_row "npm pkg $n"        "$(describe_npm "$n")"
  print_row "npm scope @$n"     "$(describe_npm_scope "$n")"
  echo
  echo "  ${C_DIM}─── GitHub user/org ───${C_RESET}"
  print_row "user/org $n"       "$(describe_github_user "$n")"
  for pre in $GH_VARIANTS_PREFIX; do
    print_row "user ${pre}${n}"   "$(describe_github_user "${pre}${n}")"
  done
  for suf in $GH_VARIANTS_SUFFIX; do
    print_row "org ${n}${suf}"    "$(describe_github_user "${n}${suf}")"
  done
  echo
  echo "  ${C_DIM}─── editor marketplaces ───${C_RESET}"
  print_row "Open VSX ns $n"    "$(describe_openvsx "$n")"
  print_row "VS Code Mkt"       "$(describe_vscode_mkt "$n")"
  echo
  echo "  ${C_DIM}─── Homebrew ───${C_RESET}"
  print_row "formula $n"        "$(describe_brew formula "$n")"
  print_row "cask $n"           "$(describe_brew cask "$n")"
  echo
  echo "  ${C_DIM}─── domains ───${C_RESET}"
  for tld in $TLD_LIST; do
    print_row "$n.$tld"         "$(describe_domain "$n.$tld")"
  done
  echo
  echo "  ${C_DIM}─── social ───${C_RESET}"
  print_row "X @$n"             "$(describe_x "$n")"
  print_row "X @${n}_ide"       "$(describe_x "${n}_ide")"
  print_row "reddit r/$n"       "$(describe_reddit "$n")"
  echo
}

for name in "$@"; do
  sweep_name "$name"
done
