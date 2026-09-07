#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# changelog-add.sh: add one entry under [Unreleased], creating the section header.
#
# Three times in one day an entry written "under the first ### Fixed below
# [Unreleased]" landed under the published section instead, because
# [Unreleased] was empty after a bump. This is the one way to add an entry.
#
# Usage: changelog-add.sh <Added|Changed|Fixed|Removed> "<one line, no leading dash>"
set -euo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd -P)"
kind="${1:?Added|Changed|Fixed|Removed}"; line="${2:?entry text}"
case "$kind" in Added|Changed|Fixed|Removed) ;; *) echo "changelog-add: kind must be Added|Changed|Fixed|Removed" >&2; exit 2 ;; esac
python3 - "$ROOT/CHANGELOG.md" "$kind" "$line" <<'PY'
import sys, re
path, kind, line = sys.argv[1], sys.argv[2], sys.argv[3].rstrip("\n")
text = open(path).read()
i = text.index("## [Unreleased]")
j = re.search(r"^## \[", text[i+5:], re.M); end = i + 5 + j.start() if j else len(text)
sec = text[i:end]
head = f"### {kind}"
if head in sec:
    k = sec.index(head) + len(head)
    # insert after the header's blank line, before the first entry
    m = re.search(r"\n\n", sec[k:]); k = k + (m.end() if m else 0)
    sec = sec[:k] + "- " + line + "\n" + sec[k:]
else:
    sec = sec.rstrip("\n") + f"\n\n{head}\n\n- {line}\n"
text = text[:i] + sec.rstrip("\n") + "\n\n" + text[end:]
text = re.sub(r"\n{3,}", "\n\n", text)
open(path, "w").write(text)
PY
echo "changelog-add: [$kind] $line"
