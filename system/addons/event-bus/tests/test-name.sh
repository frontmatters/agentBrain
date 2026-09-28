#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# brain-name must give the names of the reference djb2 adjective-animal generator.
# The expected values below come from that reference, not from this script.
set -uo pipefail

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
pass=0; fail=0
check() {
	if [ "$2" = "$3" ]; then pass=$((pass + 1))
	else fail=$((fail + 1)); echo "FAIL: $1: got '$2', want '$3'" >&2; fi
}

check "web key"         "$("$BIN/brain-name" web:deadbeef)"      "wise-lemur"
check "local"           "$("$BIN/brain-name" local)"             "rosy-koala"
check "mac key"         "$("$BIN/brain-name" aa:1b:c4:9f:2e:70)" "rosy-puffin"
check "agent key"       "$("$BIN/brain-name" agent:1234abcd)"    "hardy-robin"
check "non-ascii key"   "$("$BIN/brain-name" héllo)"             "calm-sparrow"
check "env default"     "$(CLAUDE_CODE_SESSION_ID=local "$BIN/brain-name")" "rosy-koala"
check "no key fails"    "$(env -u CLAUDE_CODE_SESSION_ID "$BIN/brain-name" >/dev/null 2>&1; echo $?)" "1"

# Drift guard: opt-in. Point BRAIN_NAME_REFERENCE at a reference implementation
# (a .swift file with `static let adjectives/animals = [...]`) to compare word lists.
SWIFT="${BRAIN_NAME_REFERENCE:-}"
if [ -n "$SWIFT" ] && [ -f "$SWIFT" ]; then
	words() { python3 -c '
import re,sys
s=open(sys.argv[1]).read()
if sys.argv[1].endswith(".swift"):
    body=re.search(r"static let "+sys.argv[2]+r" = \[(.*?)\]",s,re.S).group(1)
    print(" ".join(re.findall(r"\"([a-z]+)\"",body)))
else:
    print(" ".join(re.search(sys.argv[2]+r"=\"(.*?)\"",s,re.S).group(1).split()))' "$1" "$2"; }
	check "adjectives match reference" "$(words "$BIN/brain-name" ADJECTIVES)" "$(words "$SWIFT" adjectives)"
	check "animals match reference"    "$(words "$BIN/brain-name" ANIMALS)"    "$(words "$SWIFT" animals)"
else
	echo "test-name: BRAIN_NAME_REFERENCE unset, drift guard skipped" >&2
fi

echo "test-name: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
