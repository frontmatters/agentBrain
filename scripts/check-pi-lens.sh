#!/usr/bin/env bash
# Inspect pi-lens local state for unresolved findings and review warnings.
# Modes:
#   default         — fail on worklog findings, warn on high-severity review issues
#   --pi-lens-strict — also fail on high-severity review issues
# CI usually has no .pi-lens directory; local doctor uses this to catch active lens errors.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STRICT=false
for arg in "$@"; do
	case "$arg" in
	--pi-lens-strict) STRICT=true ;;
	*)
		echo "Unknown flag: $arg" >&2
		exit 1
		;;
	esac
done

python3 - - "$STRICT" <<'PY'
import json
import sys
import os
from pathlib import Path

strict = len(sys.argv) > 1 and sys.argv[-1].lower() == 'true'

roots = [p for p in Path('.').rglob('.pi-lens') if '.git' not in p.parts and 'local' not in p.parts]
if not roots:
    print('pi-lens check skipped: no .pi-lens state found.')
    raise SystemExit(0)

# ── Worklog findings (always fail) ────────────────────

failures = []
for root in roots:
    worklog = root / 'worklog.jsonl'
    if worklog.exists() and worklog.stat().st_size > 0:
        rows = []
        for line in worklog.read_text(errors='ignore').splitlines():
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                rows.append({'message': line, 'rule': 'unparseable'})
        if rows:
            failures.append((root, rows))

if failures:
    print('pi-lens check failed. Unresolved worklog findings:', file=sys.stderr)
    for root, rows in failures:
        print(f'  {root}: {len(rows)} finding(s)', file=sys.stderr)
        for row in rows[:20]:
            file_path = Path(row.get('filePath', '')).name or row.get('filePath', '?')
            line = row.get('line', '?')
            rule = row.get('rule', '?')
            message = row.get('message', '')
            print(f'    {file_path}:{line} {rule} — {message}', file=sys.stderr)
        if len(rows) > 20:
            print(f'    ... and {len(rows) - 20} more', file=sys.stderr)
    print('\nFix the findings or clear stale .pi-lens/worklog.jsonl after verifying they are obsolete.', file=sys.stderr)
    raise SystemExit(1)

# ── Review summary (warn or fail) ─────────────────────

warnings = []
for root in roots:
    review_dir = root / 'reviews'
    if not review_dir.is_dir():
        continue

    # Find latest review JSON. Sort by filename (the scan timestamp is embedded
    # in the name); mtime is unreliable — copied review files share one mtime,
    # which made this selection arbitrary and could surface a stale review.
    reviews = sorted(review_dir.glob('*.json'), key=lambda p: p.name, reverse=True)
    if not reviews:
        continue

    latest = reviews[0]
    try:
        data = json.loads(latest.read_text(errors='ignore'))
    except Exception:
        continue

    by_cat = data.get('byCategory', {})
    if not isinstance(by_cat, dict):
        continue

    for cat, val in by_cat.items():
        if not isinstance(val, dict):
            continue
        severity = val.get('severity', '?')
        count = val.get('count', 0)
        if count > 0:
            warnings.append((severity, cat, count, latest.parent.parent))

if warnings:
    # Categorize by severity. Anything neither critical nor caution (e.g. 🟢)
    # is informational: shown for visibility, never a failure — not even strict.
    critical = [(s, c, n, r) for s, c, n, r in warnings if '🔴' in s]
    caution  = [(s, c, n, r) for s, c, n, r in warnings if '🟡' in s or '🟠' in s]
    info     = [w for w in warnings if w not in critical and w not in caution]

    if strict and (critical or caution):
        print('pi-lens check failed (strict). Review findings:', file=sys.stderr)
        for sev, cat, count, root in critical + caution:
            print(f'  {sev} {cat}: {count} issue(s) [{root}]', file=sys.stderr)
        raise SystemExit(1)
    elif critical:
        print('pi-lens review warnings (high severity):')
        for sev, cat, count, root in critical:
            print(f'  {sev} {cat}: {count} issue(s) [{root}]')
        if strict:
            raise SystemExit(1)
    elif caution:
        print('pi-lens review notes (low/medium severity):')
        for sev, cat, count, root in caution:
            print(f'  {sev} {cat}: {count} issue(s) [{root}]')
    elif info:
        print('pi-lens review notes (informational):')
        for sev, cat, count, root in info:
            print(f'  {sev} {cat}: {count} issue(s) [{root}]')

    total = sum(n for _, _, n, _ in warnings)
    print(f'  ({total} total across {len(warnings)} categories)')

print('pi-lens check passed.')
PY
