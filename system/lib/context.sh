#!/usr/bin/env bash
# context.sh — sourceable. Defines infer_context(): resolve the WRITE CONTEXT
# (which space, if any) for a note from PATH-based and explicit signals only.
#
# Never content-based: tech-stack (Lit, PocketBase, …) is shared across projects,
# so content inference produces false positives. See the spaces-context-model
# design note. Signals, in priority order:
#
#   6  env AGENTBRAIN_CONTEXT / AGENTBRAIN_SPACE   — explicit override, wins
#   1/2 the FILE being written: its path under local/spaces/<slug>/, or its
#      frontmatter `space:`  — positional signals DOMINATE the CWD, so a
#      mid-session `cd` never switches context
#   5  CWD under a known code-root (longest-prefix match, from .space-map.json)
#   4  git remote basename of the CWD repo → alias   (secondary)
#
# Echoes on stdout exactly one of:
#   <slug>      a confident space determination
#   ambiguous   the FILE lives in space X's subtree but its frontmatter claims
#               space Y (a misfiled note) — caller should refuse, not guess
#   unknown     no space signal — caller decides (personal/main-vault, ask, refuse)
#
# The reverse-map (local/.space-map.json) is built by scripts/build-space-map.sh;
# a missing or stale map degrades gracefully (map-dependent signals simply drop
# out, biasing toward "unknown" rather than a wrong space).
#
# Usage (sourceable):
#   source system/lib/context.sh
#   ctx="$(infer_context "path/to/note.md")"   # FILE optional

# Repo root = two dirs up from this file (system/lib/context.sh), captured at SOURCE
# time: ${BASH_SOURCE[0]} is reliable at a file's top level but can be EMPTY inside a
# function called from a bare command line (→ dirname "" = ".", wrong root). CDPATH=''
# so a relative source path never resolves against the user's CDPATH.
_CONTEXT_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
_context_root() { printf '%s\n' "$_CONTEXT_ROOT"; }

infer_context() {
	local file="${1:-}" root
	root="$(_context_root)"
	# Auto-regen the reverse-map when missing or stale (a passport changed since it
	# was built), so code-root inference stays correct without a manual step.
	# Best-effort + gitignored; a partial checkout (no generator) just skips it.
	if [ -d "$root/local/spaces" ] && [ -x "$root/scripts/build-space-map.sh" ]; then
		if [ ! -f "$root/local/.space-map.json" ] ||
			[ -n "$(find "$root/local/spaces" -name index.md -newer "$root/local/.space-map.json" 2>/dev/null | head -n1)" ]; then
			bash "$root/scripts/build-space-map.sh" >/dev/null 2>&1 || true
		fi
	fi
	python3 - "$root" "$file" "$PWD" "$HOME" "${AGENTBRAIN_CONTEXT:-${AGENTBRAIN_SPACE:-}}" <<'PY'
import json, os, re, sys

root, file, pwd, home, env = sys.argv[1:6]
map_path = os.path.join(root, 'local', '.space-map.json')

try:
    m = json.load(open(map_path, encoding='utf-8'))
except Exception:
    m = {}
by_alias = m.get('by-alias', {})
by_code_root = m.get('by-code-root', {})

def out(s):
    print(s)
    sys.exit(0)

# 6 — explicit env override wins (resolve through aliases; trust unknown values).
if env:
    out(by_alias.get(env, env))

# 1/2 — the file being written. Positional signals dominate the CWD.
if file:
    absf = os.path.normpath(file if os.path.isabs(file) else os.path.join(pwd, file))
    mo = re.search(r'/local/spaces/([^/]+)/', absf.replace(os.sep, '/') + '/')
    path_slug = mo.group(1) if mo else None
    fm_slug = None
    try:
        head = open(absf, encoding='utf-8', errors='replace').read(4000)
        fmm = re.search(r'^space:\s*(\S+)\s*$', head, re.M)
        fm_slug = fmm.group(1) if fmm else None
    except OSError:
        pass
    if path_slug and fm_slug and path_slug != fm_slug:
        out("ambiguous")
    if path_slug:
        out(path_slug)
    if fm_slug:
        out(fm_slug)

# 5 — CWD under a known code-root (longest-prefix match).
npwd = os.path.normpath(pwd)
best = None
for cr, slug in by_code_root.items():
    ncr = os.path.normpath(cr)
    if npwd == ncr or npwd.startswith(ncr + os.sep):
        if best is None or len(ncr) > len(best[0]):
            best = (ncr, slug)
if best:
    out(best[1])

# 4 — git remote basename of the CWD repo → alias (secondary).
d = npwd
while True:
    gc = os.path.join(d, '.git', 'config')
    if os.path.isfile(gc):
        try:
            cfg = open(gc, encoding='utf-8', errors='replace').read()
            for u in re.findall(r'url\s*=\s*(\S+)', cfg):
                base = re.sub(r'\.git$', '', u.rstrip('/').split('/')[-1])
                if base in by_alias:
                    out(by_alias[base])
        except OSError:
            pass
        break
    nd = os.path.dirname(d)
    if nd == d:
        break
    d = nd

out("unknown")
PY
}
