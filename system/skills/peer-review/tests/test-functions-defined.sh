#!/usr/bin/env bash
# Regression test for the "archive_completed_event: command not found" class of
# bug: a rename left a call-site pointing at a function that no longer exists.
# Bash only catches this at runtime, on the exact path that calls it — so a
# rarely-hit branch (--wait + --archive together) can hide it for months.
#
# This is a static check: every internal-looking function call must resolve to a
# definition in the same file. Catches future rename leftovers regardless of
# which code path triggers them.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../bin/peer-review"
fail=0

# 1. Syntax must parse.
if bash -n "$SCRIPT"; then
  echo "  ok   bash -n parses"
else
  echo "  FAIL bash -n syntax error"; fail=1
fi

# Comment-stripped copy (commented refs and # in URLs must not count as code).
CLEAN="$(sed 's/#.*//' "$SCRIPT")"

# 2. Every defined function name — including nested/indented ones (yaml_safe is
#    defined inside archive_mode), hence the leading [[:space:]]*.
defined="$(printf '%s\n' "$CLEAN" | grep -oE '^[[:space:]]*[a-z_][a-z0-9_]*\(\)' \
  | grep -oE '[a-z_][a-z0-9_]*' | sort -u)"

# 3. Detect calls via the UNAMBIGUOUS shape only: a name at statement start
#    followed by a quoted/$ argument — `name "$x"`, `name "..."`, `name $x`.
#    This is reliably a function (or command) call: assignments have `=` with no
#    space, jq object keys have `:`, definitions have `()`. Avoids the false
#    positives from jq-string field names and heredocs that a broad scan hits.
called="$(printf '%s\n' "$CLEAN" \
  | grep -oE '^[[:space:]]*[a-z_][a-z0-9_]*[[:space:]]+["'\''$]' \
  | grep -oE '[a-z_][a-z0-9_]*' | sort -u)"

# 4. Any such call that is neither a defined function nor a known external is a
#    dangling reference (the bug class).
# Shell keywords/builtins + external tools that can appear as `word "$arg"` but
# are not internal functions.
KNOWN_EXTERNALS=" git jq cat echo printf sed grep awk date mkdir rm cp mv tr head tail sort uniq wc python3 bash sleep read return exit local export \
  case eval source command test declare typeset readonly unset shift trap wait kill cd set if while until for select function time then else do done fi elif in "
missing=""
while IFS= read -r name; do
  [ -z "$name" ] && continue
  printf '%s\n' "$defined" | grep -qx "$name" && continue
  case "$KNOWN_EXTERNALS" in *" $name "*) continue ;; esac
  missing="$missing $name"
done <<< "$called"

# Whitelist of legitimate external commands with underscores (extend as needed).
WHITELIST=""
filtered=""
for n in $missing; do
  case " $WHITELIST " in *" $n "*) ;; *) filtered="$filtered $n" ;; esac
done

if [ -n "${filtered// /}" ]; then
  echo "  FAIL called but not defined:$filtered"; fail=1
else
  echo "  ok   every internal function call resolves to a definition"
fi

# 5. Explicit guard for the exact regression.
if printf '%s\n' "$defined" | grep -qx archive_completed_event; then
  echo "  ok   archive_completed_event is defined (the original bug)"
else
  echo "  FAIL archive_completed_event referenced by --wait flow but not defined"; fail=1
fi

echo ""
[ "$fail" -eq 0 ] && echo "  PASS" || echo "  FAILED"
exit "$fail"
