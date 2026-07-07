#!/usr/bin/env bash
# build-space-map.sh — generate local/.space-map.json from the space passports.
#
# Part of the spaces-context-model: context inference must never be content-based
# (tech-stack is shared across projects → false positives). It is PATH-based. This
# script builds the path→space lookup that scripts/../system/lib/context.sh reads:
#
#   local/.space-map.json
#   {
#     "by-code-root": { "/abs/expanded/code-root": "<slug>", ... },
#     "by-alias":     { "<alias>": "<slug>", ..., "<slug>": "<slug>" }
#   }
#
# Source of truth: each local/spaces/<slug>/index.md frontmatter (`slug`,
# `aliases`, `code-roots`). Regenerate whenever a space's code-roots/aliases
# change — analogous to .parks-index.json. Idempotent: same passports → byte-identical
# output (keys sorted). The file is gitignored (holds absolute paths; machine-local).
#
# NB: this reads only passport frontmatter (slug/aliases/code-roots) — never note
# bodies — so it does not breach the space seal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPACES_DIR="$ROOT/local/spaces"
OUT="$ROOT/local/.space-map.json"

if [ ! -d "$SPACES_DIR" ]; then
	printf '{\n  "by-alias": {},\n  "by-code-root": {}\n}\n' >"$OUT"
	echo "build-space-map: no spaces/ dir — wrote empty map to $OUT"
	exit 0
fi

python3 - "$SPACES_DIR" "$OUT" "$HOME" <<'PY'
import json, os, re, sys

spaces_dir, out, home = sys.argv[1], sys.argv[2], sys.argv[3]

def parse_list(line):
    # `key: [a, b, c]` → [a,b,c]; also tolerate a bare scalar `key: a`.
    m = re.search(r'\[(.*)\]', line)
    if m:
        raw = m.group(1)
    else:
        raw = line.split(':', 1)[1] if ':' in line else ''
    return [x.strip() for x in raw.split(',') if x.strip()]

def expand(p):
    if p.startswith('~'):
        p = home + p[1:]
    return os.path.normpath(os.path.expandvars(p))

by_code_root, by_alias = {}, {}

for name in sorted(os.listdir(spaces_dir)):
    idx = os.path.join(spaces_dir, name, 'index.md')
    if not os.path.isfile(idx):
        continue
    txt = open(idx, encoding='utf-8', errors='replace').read()
    parts = txt.split('---', 2)
    if len(parts) < 3:
        continue  # no frontmatter block
    front = parts[1]
    slug, aliases, code_roots = name, [], []
    for line in front.splitlines():
        if re.match(r'^slug:', line):
            slug = line.split(':', 1)[1].strip()
        elif re.match(r'^aliases:', line):
            aliases = parse_list(line)
        elif re.match(r'^code-roots:', line):
            code_roots = parse_list(line)
    by_alias[slug] = slug            # a slug always resolves to itself
    for a in aliases:
        by_alias[a] = slug
    for r in code_roots:
        by_code_root[expand(r)] = slug

data = {"by-alias": by_alias, "by-code-root": by_code_root}
with open(out, 'w', encoding='utf-8') as fh:
    fh.write(json.dumps(data, indent=2, sort_keys=True) + "\n")

print(f"build-space-map: {len(by_code_root)} code-root(s), {len(by_alias)} alias(es) → {out}")
PY
