#!/usr/bin/env bash
# sweep-trademark.sh — OPT-IN trademark clearance for ONE finalist name.
#
# Deliberately NOT part of sweep.sh. The registers block scripted access:
#   - TMview (tmdn.org) is network-blocked from curl (HTTP 000)
#   - WIPO branddb API needs an ALTCHA proof-of-work + auth token (403/401)
#   - EUIPO / BOIP are SPA + auth
# Only a REAL browser solves the ALTCHA (it's a compute challenge, not a human
# CAPTCHA). This drives the `sitescope` CDP browser through the WIPO Global Brand
# Database — which aggregates Benelux (BX) + EUIPO (EM) + national + Madrid marks —
# and returns the result rows out of the DOM (parseable, no vision needed) plus a
# screenshot.
#
# Trademark is a JUDGEMENT call (active vs expired, Nice-class overlap, territory),
# so this is agent-in-loop by design: the script gets the browser to the answer;
# the agent reads and judges it. Run it only for the top 1-2 names, never the whole
# shortlist (one browser spin-up per name).
#
# Usage:  bash sweep-trademark.sh <name>
# Needs:  the `sitescope` skill on PATH (CDP browser).
#
# For software/app names the classes that matter: 9 (software), 42 (SaaS / software
# services); sometimes 38 (telecom), 35 (advertising/retail).
set -euo pipefail

NAME="${1:-}"
[ -n "$NAME" ] || { echo "usage: sweep-trademark.sh <name>" >&2; exit 2; }

DB="https://branddb.wipo.int/branddb/en/"
SHOT="/tmp/trademark-${NAME}.png"

if ! command -v sitescope >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: 'sitescope' is not on PATH — the trademark step needs a real (CDP) browser.
Manual route instead:
  1. Open $DB
  2. Search the brand name "$NAME"
  3. Read each hit's STATUS (Registered = live; Expired/Withdrawn = not a blocker)
     and its Nice classes; a live mark in class 9/42 for Benelux/EU is a conflict.
EOF
  exit 1
fi

echo "==> WIPO Global Brand Database — brand name contains '$NAME'"
sitescope open "$DB" --settle 5000 >/dev/null 2>&1

# Locate the brand-name searchbox (first textbox) + the Search button from one
# interactive snapshot. Refs expire per snapshot, so use them immediately.
snap="$(sitescope snapshot -i 2>/dev/null || true)"
box="$(printf '%s\n' "$snap" | grep -E '\[textbox\]'        | head -1 | grep -oE '@e[0-9]+' || true)"
btn="$(printf '%s\n' "$snap" | grep -iE '\[button\].*search'| head -1 | grep -oE '@e[0-9]+' || true)"
if [ -z "$box" ] || [ -z "$btn" ]; then
  echo "ERROR: could not find the WIPO search box/button (layout changed?)." >&2
  printf '%s\n' "$snap" | head -20 >&2
  exit 1
fi

sitescope fill "$box" "$NAME" >/dev/null 2>&1
sitescope click "$btn"        >/dev/null 2>&1
sleep 5
sitescope shot "$SHOT" --full >/dev/null 2>&1 || true

# Pull the results text out of the DOM. sitescope eval returns JSON; decode it.
raw="$(sitescope eval 'document.body.innerText' 2>/dev/null || true)"
txt="$(printf '%s' "$raw" | python3 -c 'import sys,json
s=sys.stdin.read()
try: print(json.loads(s))
except Exception: print(s)' 2>/dev/null || printf '%s' "$raw")"

echo
echo "==> Results (from the WIPO DOM):"
# Print the results block from the "Displaying N results" line onward, so each hit's
# owner / Nice classes / country / STATUS values come through (they sit on their own
# lines in innerText, right under their labels).
printf '%s\n' "$txt" \
  | awk 'tolower($0) ~ /displaying|no +results?|[0-9]+ +results?/{f=1} f' \
  | awk 'NF' | sed 's/^[[:space:]]*/    /' | head -34
echo
echo "==> Screenshot: $SHOT"
echo "==> Judge:"
echo "    - STATUS per hit: Registered/Pending = live blocker; Expired/Withdrawn = not."
echo "    - Territory: a Benelux (BX) or EU (EM) mark reaches the Netherlands; a lone"
echo "      national mark elsewhere (e.g. France) does not."
echo "    - Overlap: conflict only if a LIVE mark shares your Nice class (9 software,"
echo "      42 SaaS). Registry-clear + brand-DB-clear is a strong signal, not legal advice."
echo "    (browser left open — 'sitescope close' when done.)"
