#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# audit-interactive.sh — static audit for every bug class seen in the field:
#   1 syntax (bash -n)                5 set -e 'cond && assignment' report
#   2 shellcheck (errors+warnings)    6 viewport clears (ESC[2J) report
#   3 $var followed by non-ASCII      7 key reads without NUL delimiter
#   4 corrupt UTF-8                   8 embedded helper <-> source drift
# Read-only; exit non-zero on any FAIL. (Functional PTY suites live in
# test-installer-prompts.sh, run by release-check.)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAIL=0

echo "1. bash -n"
for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/installer/*.sh "$ROOT"/scripts/lib/*.sh; do
	bash -n "$f" 2>/dev/null || { echo "  FAIL syntax: $f"; FAIL=1; }
done
echo "  PASS"

echo "2. shellcheck (error+warning)"
out="$(shellcheck -s bash -S warning \
	"$ROOT"/scripts/*.sh "$ROOT"/scripts/installer/*.sh "$ROOT"/scripts/lib/*.sh 2>&1 |
	grep -E ':[0-9]+:[0-9]+: (error|warning)')" || true
if [ -n "$out" ]; then echo "$out" | head -10; FAIL=1; else echo "  PASS"; fi

echo "3. \$var directly followed by a non-ASCII byte"
python3 - "$ROOT" <<'PY' || FAIL=1
import re, glob, sys
hits = []
for f in glob.glob(sys.argv[1] + "/scripts/**/*.sh", recursive=True):
    s = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]", s):
        hits.append(f"{f}:{s[:m.start()].count(chr(10))+1}: {m.group(0)!r}")
print("\n".join(hits) if hits else "  PASS")
sys.exit(1 if hits else 0)
PY

echo "4. corrupt UTF-8"
python3 - "$ROOT" <<'PY' || FAIL=1
import glob, sys
bad = []
for f in glob.glob(sys.argv[1] + "/scripts/**/*.sh", recursive=True):
    raw = open(f, "rb").read()
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as e:
        bad.append(f"{f}: {e}")
print("\n".join(bad) if bad else "  PASS")
sys.exit(1 if bad else 0)
PY

echo "5. set -e 'cond && assignment' (report — bash ignores first-member failures)"
grep -rn '] && [a-zA-Z_]*=' "$ROOT/scripts/lib/capability-install.sh" \
	"$ROOT/scripts/installer/prompt-helper.sh" "$ROOT/scripts/installer/install.sh" \
	"$ROOT/scripts/tools/install-agent-clis.sh" "$ROOT/scripts/tools/install-prerequisites.sh" \
	"$ROOT/scripts/configure-pi.sh" 2>/dev/null |
	grep -vE '#|&& \[\[|\[\[ ' | sed 's/^/  note: /' || true
echo "  (informational)"

echo "6. viewport clears (ESC[2J) outside the intro animation"
out="$(grep -rn '\\033\[2J' "$ROOT/scripts/installer/install.sh" "$ROOT/scripts/tools/install-agent-clis.sh" 2>/dev/null |
	grep -v '2K' | grep -v 'audit-ok' | sed 's/^/  found: /')" || true
if [ -n "$out" ]; then echo "$out"; else echo "  PASS (intro animation only, by design)"; fi

echo "7. key reads with NUL delimiter"
if grep -q "read -r -s -d ''" "$ROOT/scripts/installer/prompt-helper.sh"; then
	echo "  PASS"
else
	echo "  FAIL: Enter-as-LF would read as EOF"; FAIL=1
fi

echo "8. embedded helper <-> source sync"
python3 - "$ROOT" <<'PY' || FAIL=1
import sys
from pathlib import Path
root = Path(sys.argv[1])
s = (root / "scripts/installer/install.sh").read_text()
a = s.index("# Embedded from scripts/installer/prompt-helper.sh")
b = s.index("clear 2>/dev/null || true", a)
emb = "\n".join(s[a:b].split("\n")[2:])
src = "\n".join((root / "scripts/installer/prompt-helper.sh").read_text().split("\n")[1:])
print("  PASS" if src.strip() == emb.strip() else "  FAIL: drift between source and embedded copy")
sys.exit(0 if src.strip() == emb.strip() else 1)
PY

if [ "$FAIL" = 0 ]; then
	echo "AUDIT PASS"
else
	echo "AUDIT FAILED"
fi
exit $FAIL
