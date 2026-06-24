#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: bash scripts/scanman-compare.sh <current-slug> <previous-slug>" >&2
  echo "Example: bash scripts/scanman-compare.sh babysitter babysitter-pass1" >&2
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

CURRENT_SLUG="$1"
PREV_SLUG="$2"
BASE="$AGENTBRAIN_DIR/local/research/repo-distill"
CURRENT_DIR="$BASE/$CURRENT_SLUG"
PREV_DIR="$BASE/$PREV_SLUG"
OUT_FILE="$CURRENT_DIR/99-compare-vs-$PREV_SLUG.md"

if [[ ! -d "$CURRENT_DIR" ]]; then
  echo "Current scanman dir not found: $CURRENT_DIR" >&2
  exit 1
fi
if [[ ! -d "$PREV_DIR" ]]; then
  echo "Previous scanman dir not found: $PREV_DIR" >&2
  exit 1
fi

CURRENT_SLUG="$CURRENT_SLUG" PREV_SLUG="$PREV_SLUG" CURRENT_DIR="$CURRENT_DIR" PREV_DIR="$PREV_DIR" OUT_FILE="$OUT_FILE" python3 - <<'PY'
from pathlib import Path
import os, re

current_slug = os.environ['CURRENT_SLUG']
prev_slug = os.environ['PREV_SLUG']
current = Path(os.environ['CURRENT_DIR'])
prev = Path(os.environ['PREV_DIR'])
out = Path(os.environ['OUT_FILE'])

expected = [
    'index.md',
    '00-file-inventory.md',
    '00b-dependency-map.md',
    '01-system-map.md',
    '02-runtime-model.md',
    '03-core-primitives.md',
    '04-risk-and-bloat.md',
    '05-redesign-v1.md',
]

confidence_re = re.compile(r'Coverage level[^:]*:\s*(.+)', re.I)
coverage_status_re = re.compile(r'- Coverage status:\s*(.+)')
checkbox_re = re.compile(r'- \[( |x)\] (.+)')


def read_text(path):
    try:
        return path.read_text()
    except Exception:
        return ''


def exists_map(root):
    return {name: (root / name).exists() for name in expected}


def extract_index_checklist(text):
    rows = []
    for line in text.splitlines():
        m = checkbox_re.match(line.strip())
        if m:
            rows.append((m.group(2).strip(), 'done' if m.group(1) == 'x' else 'todo'))
    return rows


def extract_coverage_status(text):
    for line in text.splitlines():
        m = coverage_status_re.match(line.strip())
        if m:
            return m.group(1).strip()
    return 'unknown'


def extract_confidences(root):
    out = {}
    for name in expected:
        p = root / name
        if not p.exists() or not p.is_file():
            continue
        text = read_text(p)
        for line in text.splitlines():
            m = confidence_re.search(line)
            if m:
                out[name] = m.group(1).strip()
                break
    return out


def deferred_lines(root):
    hits = []
    for name in expected:
        p = root / name
        if not p.exists() or not p.is_file():
            continue
        for line in read_text(p).splitlines():
            if 'deferred' in line.lower():
                hits.append((name, line.strip()))
    return hits

cur_exists = exists_map(current)
prev_exists = exists_map(prev)
cur_index = read_text(current / 'index.md')
prev_index = read_text(prev / 'index.md')
cur_check = dict(extract_index_checklist(cur_index))
prev_check = dict(extract_index_checklist(prev_index))
cur_cov = extract_coverage_status(cur_index)
prev_cov = extract_coverage_status(prev_index)
cur_conf = extract_confidences(current)
prev_conf = extract_confidences(prev)
cur_def = deferred_lines(current)
prev_def = deferred_lines(prev)

lines = []
lines += [f'# 99 Compare — {current_slug} vs {prev_slug}', '', '## Purpose', 'Compare two scanman runs so another agent can see what improved, what changed, and what remains uncertain.', '', '## Compared Runs', f'- Current: `{current}`', f'- Previous: `{prev}`', '', '## Output Presence Diff', '| File | Current | Previous | Notes |', '|---|---|---|---|']
for name in expected:
    c = 'yes' if cur_exists[name] else 'no'
    p = 'yes' if prev_exists[name] else 'no'
    note = 'new in current' if c == 'yes' and p == 'no' else ('missing in current' if c == 'no' and p == 'yes' else '')
    lines.append(f'| `{name}` | {c} | {p} | {note} |')

lines += ['', '## Index Checklist Diff', '| Output | Current | Previous |', '|---|---|---|']
all_keys = sorted(set(cur_check) | set(prev_check))
for key in all_keys:
    lines.append(f'| {key} | {cur_check.get(key, "—")} | {prev_check.get(key, "—")} |')

lines += ['', '## Coverage Status Diff', f'- Current coverage status: `{cur_cov}`', f'- Previous coverage status: `{prev_cov}`', '', '## Confidence Diff', '| File | Current | Previous |', '|---|---|---|']
all_conf = sorted(set(cur_conf) | set(prev_conf))
for key in all_conf:
    lines.append(f'| `{key}` | {cur_conf.get(key, "—")} | {prev_conf.get(key, "—")} |')

lines += ['', '## Deferred Areas Snapshot', '### Current']
if cur_def:
    for name, line in cur_def[:20]:
        lines.append(f'- `{name}` — {line}')
else:
    lines.append('- No explicit deferred lines found')
lines += ['', '### Previous']
if prev_def:
    for name, line in prev_def[:20]:
        lines.append(f'- `{name}` — {line}')
else:
    lines.append('- No explicit deferred lines found')

new_files = [name for name in expected if cur_exists[name] and not prev_exists[name]]
missing_files = [name for name in expected if prev_exists[name] and not cur_exists[name]]
lines += ['', '## Summary', '### Improvements']
if new_files:
    for name in new_files:
        lines.append(f'- Added `{name}` in current run')
if cur_cov != prev_cov:
    lines.append(f'- Coverage status changed from `{prev_cov}` to `{cur_cov}`')
if not new_files and cur_cov == prev_cov:
    lines.append('- No obvious structural improvements detected automatically; inspect content-level changes manually')

lines += ['', '### Regressions / Gaps']
if missing_files:
    for name in missing_files:
        lines.append(f'- `{name}` exists in previous run but not in current run')
else:
    lines.append('- No missing expected files detected automatically')

lines += ['', '### Recommended Next Step', '- Review content-level differences in system/runtime/dependency maps', '- Continue the current run from the first incomplete artifact', '- Update confidence labels if coverage deepens materially']

out.write_text('\n'.join(lines) + '\n')
PY

echo "Wrote compare report: $OUT_FILE"
