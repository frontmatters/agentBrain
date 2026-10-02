"""factory-discover.py: find the factories under a root, the one way.

factory-registry.sh and factory-paths.sh both list factories; they import this
instead of each walking the tree their own way.
"""
import json, pathlib

LAYOUT = json.loads((pathlib.Path(__file__).resolve().parent.parent / "layout.json").read_text())


def factories(root):
    root = pathlib.Path(root).expanduser().resolve()
    layout = LAYOUT
    # <tool>.factory at any depth up to factoryDepth (~/Developer/<area>/<client>/x.factory),
    # plus any factory.json directly under the root (older names, see legacyName).
    # A factory inside another factory (a lane, R&D/legacy) is not listed.
    suffix, depth = layout['factorySuffix'], layout['factoryDepth']
    found, level = [], [root]
    for d in range(1, depth+1):
        nxt = []
        for parent in level:
            try: children = sorted(p for p in parent.iterdir() if p.is_dir() and not p.name.startswith('.') and p.name != 'node_modules')
            except OSError: continue
            for c in children:
                if (c/'factory.json').is_file() and (d == 1 or c.name.endswith(suffix)): found.append(c/'factory.json')
                elif not (c/'factory.json').is_file(): nxt.append(c)
        level = nxt
    return sorted(c for c in found if not worktree_of_other_factory(c.parent))


def worktree_of_other_factory(d):
    # A git worktree of a factory (a release or LAN branch checked out beside
    # it) carries that factory's factory.json but is not a second factory.
    g = d / '.git'
    if not g.is_file(): return False
    line = g.read_text(errors='ignore').strip()
    if not line.startswith('gitdir:'): return False
    gitdir = pathlib.Path(line.split(':', 1)[1].strip())
    if not gitdir.is_absolute(): gitdir = (d / gitdir).resolve()
    parts = gitdir.parts
    if '.git' not in parts: return False
    owner = pathlib.Path(*parts[:parts.index('.git')])
    return owner.resolve() != d.resolve() and (owner / 'factory.json').is_file()
