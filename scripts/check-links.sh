#!/usr/bin/env bash
# Check Obsidian-style wiki links in markdown files.
# Public links are a hard gate; local/ links are warn-only (private graph).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
from collections import Counter
import re
import sys

root = Path('.')
exclude_parts = {'.git', 'node_modules'}
exclude_prefixes = [Path('system/pi-config/extensions/.pi-lens')]

# Partition once: public layer vs the private local/ layer.
public_files, local_files = [], []
for path in root.rglob('*.md'):
    if set(path.parts) & exclude_parts:
        continue
    if any(path.is_relative_to(prefix) for prefix in exclude_prefixes):
        continue
    (local_files if 'local' in path.parts else public_files).append(path)

def stem_set(files):
    stems = {}
    for path in files:
        stems.setdefault(path.stem.lower(), []).append(path)
        # A folder with index.md / SKILL.md / README.md is addressable by its
        # folder name. agentBrain's skill+addon convention uses SKILL.md (not
        # index.md) as the canonical entry, so links like [[onboard]] or
        # [[event-bus]] should resolve via the folder name.
        if path.name.lower() in ('index.md', 'skill.md', 'readme.md'):
            stems.setdefault(path.parent.name.lower(), []).append(path)
    return stems

# Public links must resolve within the public layer (the repo cannot depend on
# gitignored local/). Local links may point at public OR local notes.
public_stems = stem_set(public_files)
all_stems = stem_set(public_files + local_files)

example_targets = {'note-name', 'wiki-links'}

def strip_code(text):
    """Drop code so shell `[[ ... ]]` tests and `[[:space:]]` POSIX classes
    are not mistaken for wiki links."""
    text = re.sub(r'(?ms)^([ \t]*)(`{3,}|~{3,})[^\n]*\n.*?^[ \t]*\2[ \t]*$', '', text)
    text = re.sub(r'`[^`\n]*`', '', text)
    return text

def unresolved(files, stems):
    out = []
    for path in files:
        text = strip_code(path.read_text(errors='ignore'))
        for raw in re.findall(r'\[\[([^\]]+)\]\]', text):
            target = raw.split('|', 1)[0].split('#', 1)[0].strip()
            if not target or '{{' in target or target.lower() in example_targets:
                continue
            # Skip shell/POSIX noise that survives outside code fences.
            if target.startswith((':', '-')) or any(c in target for c in '$=<>'):
                continue
            # `forward:` is an Obsidian-style forward-declaration prefix used by
            # the peer-review skill (and potentially others) to mark links that
            # are intentionally written before the target note exists. They
            # signal future work, not broken links.
            if target.lower().startswith('forward:'):
                continue
            if Path(target).stem.lower() not in stems:
                out.append((path, raw))
    return out

# Concern: wiki-link resolution. Strictness gradient — public is a hard gate,
# local is a private-hygiene warning (your own Obsidian graph, never blocks).
public_missing = unresolved(public_files, public_stems)
local_missing = unresolved(local_files, all_stems)

if public_missing:
    print('Wiki link check failed. Missing public targets:', file=sys.stderr)
    for path, raw in public_missing[:100]:
        print(f'  {path}: [[{raw}]]', file=sys.stderr)
    if len(public_missing) > 100:
        print(f'  ... and {len(public_missing) - 100} more', file=sys.stderr)

if local_missing:
    # Group by target so a link repeated across many notes is one line, not
    # one per note — keeps the warning a short, actionable signal.
    counts = Counter()
    example = {}
    for path, raw in local_missing:
        key = raw.split('|', 1)[0].split('#', 1)[0].strip()
        counts[key] += 1
        example.setdefault(key, path)
    uniq = counts.most_common()
    print(f'Wiki link check: {len(local_missing)} unresolved local link(s) across {len(uniq)} target(s) (warning — review or remove):')
    for key, n in uniq[:40]:
        suffix = f' ({n}×)' if n > 1 else ''
        print(f'  ⚠ [[{key}]]{suffix} — e.g. {example[key]}')
    if len(uniq) > 40:
        print(f'  ... and {len(uniq) - 40} more target(s)')

if public_missing:
    sys.exit(1)

if not local_missing:
    print('Wiki link check passed.')
else:
    print(f'Wiki link check passed (public clean; {len(local_missing)} local warning(s)).')
PY
