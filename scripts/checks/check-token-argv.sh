#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Static guard for secret-bearing command arguments. Only tracked source files.
set -euo pipefail
root="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != --root ] || [ ! -d "$2" ]; then
    echo 'usage: check-token-argv.sh [--root DIR]' >&2; exit 2
  fi
  root="$(cd "$2" && pwd -P)"
fi
if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "usage: --root must be a git checkout" >&2; exit 2
fi
python3 - "$root" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
paths = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '-z']).split(b'\0')
variable = r'\$(?:\{[A-Za-z_][A-Za-z_0-9]*(?::?[-+?][^}]*)?\}|[A-Za-z_][A-Za-z_0-9]*)'
# Deliberately narrow: report arguments that carry variables, not names of
# variables, stdin/config-file paths, or empty keychain passwords.
patterns = [
    ('git extraHeader', re.compile(r'-c\s+(?:["\']?)http\.extraHeader=[^\n]*?Authorization[^\n]*?' + variable, re.I)),
    ('curl header', re.compile(r'(?:-H|--header)\s+["\']Authorization:\s*(?:Bearer|token|Basic)\s+' + variable, re.I)),
    ('curl basic auth', re.compile(r'\bcurl\b[^\n]*?\s(?:-u|--user)\s+["\']?[^\s"\']*:' + variable)),
    ('keychain password', re.compile(r'\bsecurity\s+add-generic-password\b[^\n]*?\s-w\s+["\']?' + variable)),
    ('keychain password', re.compile(r'\bsecurity\s+(?:create-keychain|unlock-keychain)\b[^\n]*?\s-p\s+["\']?' + variable)),
    ('secrets value', re.compile(r'\bsecrets\s+add\s+\S+\s+\S+\s+["\']?' + variable)),
]
count = 0
scanned = 0
for raw in paths:
    if not raw:
        continue
    name = os.fsdecode(raw)
    if Path(name).suffix.lower() not in ('.sh', '.ts', '.js', '.py'):
        continue
    path = root / name
    if not path.is_file() or path.is_symlink():
        continue
    scanned += 1
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except (UnicodeError, OSError):
        continue
    for line_no, line in enumerate(lines, 1):
        if line.lstrip().startswith(('#', '//', '*', "'", 'printf ')):
            # Standalone shell string literals (fixture data) and printf
            # payloads are not commands executing the forbidden option.
            continue
        for label, pattern in patterns:
            if pattern.search(line):
                print(f'FAIL {name}:{line_no}: {label} in command argument')
                count += 1
                break
if count:
    print(f'check-token-argv: FAIL ({count} finding(s), {scanned} source files scanned)')
    sys.exit(1)
print(f'check-token-argv: PASS ({scanned} source files scanned)')
PY
