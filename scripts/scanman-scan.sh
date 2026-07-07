#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: bash scripts/scanman-scan.sh <repo-path> [repo-slug]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

REPO_PATH="$(cd "$1" && pwd)"
REPO_SLUG="${2:-$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-') }"
REPO_SLUG="${REPO_SLUG%-}"
TARGET_DIR="$AGENTBRAIN_DIR/local/research/repo-distill/$REPO_SLUG"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Scanman target missing: $TARGET_DIR" >&2
  echo "Run: bash scripts/scanman-init.sh $REPO_SLUG '$REPO_PATH'" >&2
  exit 1
fi

INV_FILE="/tmp/${REPO_SLUG}-scanman-file-inventory.txt"
find "$REPO_PATH" \
  \( -path '*/node_modules/*' -o -path '*/.git/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
  \( -name '*.ts' -o -name '*.js' -o -name '*.cjs' -o -name '*.mjs' -o -name '*.md' -o -name '*.json' -o -name '*.sh' \) -print \
  | sed "s#^$REPO_PATH/##" | sort > "$INV_FILE"

REPO_PATH="$REPO_PATH" REPO_SLUG="$REPO_SLUG" INV_FILE="$INV_FILE" TARGET_DIR="$TARGET_DIR" AGENTBRAIN_DIR="$AGENTBRAIN_DIR" python3 - <<'PY'
from pathlib import Path
import json, os, re


def should_preserve_enriched(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        text = path.read_text()
    except Exception:
        return False
    return ('Analysis status: manually enriched' in text) or ('Analysis status: verified' in text) or ('Claim discipline: verified-only main path' in text)


def should_preserve_distill(path: Path) -> bool:
    """Enriched if any table row contains a claim-label as a cell value.

    Templates have `Claim Level` as a column HEADER but empty cells.
    Enriched files have `verified`/`inferred`/`unknown`/`verified-bet` as cell values.
    Looking for a label preceded by `|` and followed by `|` (i.e. a table cell)
    cleanly distinguishes filled from empty without depending on column count.
    """
    if not path.exists():
        return False
    try:
        text = path.read_text()
    except Exception:
        return False
    if path.name not in {'03-core-primitives.md', '04-risk-and-bloat.md', '05-redesign-v1.md'}:
        return False
    return bool(re.search(r'\|\s*(?:verified|inferred|unknown|verified-bet)\b[^|\n]*\|', text))

repo = Path(os.environ['REPO_PATH'])
slug = os.environ['REPO_SLUG']
inv_file = Path(os.environ['INV_FILE'])
target = Path(os.environ['TARGET_DIR'])
agentbrain_dir = Path(os.environ['AGENTBRAIN_DIR'])

# Canonical scanman method version (single source of truth)
version_file = agentbrain_dir / 'system' / 'skills' / 'scanman' / 'VERSION'
scanman_version = version_file.read_text().strip() if version_file.exists() else 'unknown'


def write_preserving_frontmatter(path: Path, body: str) -> None:
    """Replace the body of a markdown file while preserving its YAML frontmatter.

    Why: scanman-init.sh writes correct UUID5-bearing frontmatter; scan must not
    wipe it when regenerating bootstrap layers. The agentBrain validate-hook
    blocks any edit on files with mismatched/missing ids.
    """
    if path.exists():
        existing = path.read_text()
        if existing.startswith('---\n'):
            end_idx = existing.find('\n---\n', 4)
            if end_idx != -1:
                fm = existing[:end_idx + 5]
                separator = '' if body.startswith('\n') else '\n'
                path.write_text(fm + separator + body)
                return
    # No existing frontmatter: this shouldn't happen in normal flow (init must run
    # first) but we write the body anyway rather than failing silently.
    path.write_text(body)
paths = inv_file.read_text().splitlines()
code_exts = {'.ts','.js','.cjs','.mjs','.md','.json','.sh'}
exclude = {'node_modules','.git','dist','build','coverage'}

# top-level counts
counts = {}
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in exclude]
    rel = os.path.relpath(root, repo)
    top = '(root)' if rel == '.' else rel.split(os.sep)[0]
    counts.setdefault(top, {'files': 0, 'code': 0})
    for f in files:
        counts[top]['files'] += 1
        if Path(f).suffix in code_exts:
            counts[top]['code'] += 1

# representative tree
entries = []
for p in sorted(repo.rglob('*')):
    rel_parts = p.relative_to(repo).parts
    if any(part in exclude for part in rel_parts):
        continue
    if len(rel_parts) > 2:
        continue
    entries.append(p.relative_to(repo).as_posix())
entries = entries[:120]

def tree_lines(items, root_name):
    out = [f"{root_name}/"]
    for item in items:
        depth = item.count('/')
        name = item.split('/')[-1]
        prefix = '│  ' * depth + '├─ '
        out.append(prefix + name + ('/' if '/' not in item and (repo / item).is_dir() else ''))
    return '\n'.join(out)

# package inventory
packages = []
for p in repo.rglob('package.json'):
    if any(part in exclude for part in p.parts):
        continue
    try:
        data = json.loads(p.read_text())
    except Exception:
        continue
    name = data.get('name') or p.parent.relative_to(repo).as_posix()
    deps = sorted((data.get('dependencies') or {}).keys())
    peer = sorted((data.get('peerDependencies') or {}).keys())
    packages.append({
        'name': name,
        'path': p.parent.relative_to(repo).as_posix(),
        'deps': deps,
        'peer': peer,
    })
package_names = {p['name'] for p in packages}

# language/framework detection
ext_counts = {}
for rel in paths:
    suffix = Path(rel).suffix.lower()
    ext_counts[suffix] = ext_counts.get(suffix, 0) + 1

lang_rules = [
    ('TypeScript', {'.ts', '.tsx', '.mts', '.cts'}),
    ('JavaScript', {'.js', '.jsx', '.mjs', '.cjs'}),
    ('Python', {'.py'}),
    ('Go', {'.go'}),
    ('Rust', {'.rs'}),
    ('Zig', {'.zig'}),
    ('Shell', {'.sh'}),
]
languages = []
for name, exts in lang_rules:
    total = sum(ext_counts.get(ext, 0) for ext in exts)
    if total:
        languages.append((name, total))

framework_hits = []
all_deps = set()
for pkg in packages:
    all_deps.update(pkg['deps'])
framework_rules = [
    ('Next.js', lambda: 'next' in all_deps),
    ('React', lambda: 'react' in all_deps or '@wterm/react' in package_names),
    ('Vue', lambda: 'vue' in all_deps or '@wterm/vue' in package_names),
    ('WebSocket', lambda: 'ws' in all_deps or any('WebSocket' in p.read_text(encoding='utf-8', errors='ignore') for p in source_files[:50])),
    ('WASM', lambda: any(p.suffix == '.zig' for p in repo.rglob('*.zig'))),
    ('Turbo', lambda: (repo / 'turbo.json').exists()),
    ('pnpm workspace', lambda: (repo / 'pnpm-workspace.yaml').exists()),
]
for label, fn in framework_rules:
    try:
        if fn():
            framework_hits.append(label)
    except Exception:
        pass

entrypoint_candidates = []
priority_names = {'main.ts','main.js','index.ts','index.js','server.ts','server.js','app.ts','app.js','page.tsx','page.jsx','cli.ts','cli.js'}
for p in sorted(repo.rglob('*')):
    if any(part in exclude for part in p.parts):
        continue
    if not p.is_file():
        continue
    if p.name not in priority_names:
        continue
    rel = p.relative_to(repo).as_posix()
    if rel.startswith('node_modules/'):
        continue
    entrypoint_candidates.append(rel)
entrypoint_candidates = entrypoint_candidates[:20]

# hotspot files by import count
hotspots = []
pat = re.compile(r'^(?:import |export .* from |const .*require\()', re.M)
source_files = []
for p in repo.rglob('*'):
    if p.suffix not in {'.ts','.js','.cjs','.mjs'}:
        continue
    if any(part in exclude for part in p.parts):
        continue
    source_files.append(p)
    try:
        text = p.read_text(encoding='utf-8')
    except Exception:
        continue
    count = len(pat.findall(text))
    if count:
        hotspots.append((count, p.relative_to(repo).as_posix()))
hotspots.sort(reverse=True)

# import-edge bootstrap graph for top hotspot files
import_patterns = [
    re.compile(r"import\s+(?:[^\n]*?\s+from\s+)?['\"]([^'\"]+)['\"]"),
    re.compile(r"export\s+[^\n]*?\s+from\s+['\"]([^'\"]+)['\"]"),
    re.compile(r"require\(\s*['\"]([^'\"]+)['\"]\s*\)"),
]
file_graph_blocks = []
for _, rel in hotspots[:10]:
    p = repo / rel
    try:
        text = p.read_text(encoding='utf-8')
    except Exception:
        continue
    edges = []
    seen = set()
    for pattern in import_patterns:
        for match in pattern.findall(text):
            dep = match.strip()
            if not dep or dep in seen:
                continue
            seen.add(dep)
            label = dep
            if dep.startswith('.'):
                base = (p.parent / dep)
                candidates = [
                    base,
                    base.with_suffix('.ts'),
                    base.with_suffix('.js'),
                    base.with_suffix('.mjs'),
                    base.with_suffix('.cjs'),
                    base / 'index.ts',
                    base / 'index.js',
                    base / 'index.mjs',
                    base / 'index.cjs',
                ]
                resolved = None
                for cand in candidates:
                    if cand.exists():
                        resolved = cand
                        break
                if resolved is not None:
                    try:
                        label = resolved.relative_to(repo).as_posix()
                    except Exception:
                        label = dep
            edges.append(label)
    if edges:
        file_graph_blocks.append(rel)
        for edge in edges[:12]:
            file_graph_blocks.append(f'  -> {edge}')

# inventory markdown
inv_md = []
inv_md += ['# 00 File Inventory', '', '## Purpose', 'Provide a coverage-oriented inventory so later analysis can show which files and areas were actually seen.', '', '## Coverage Policy', '- List all architecturally relevant files/paths that should be reviewed', '- Separate full inventory from core-focus shortlist', '- Mark deep/huge areas that were sampled instead of exhaustively read', '', '## Inventory Summary', f'- Repo root: `{repo}`', f'- Total inventoried files (code/docs-ish filter): {len(paths)}', "- Inventory filter used: `*.ts, *.js, *.cjs, *.mjs, *.md, *.json, *.sh`", '', '## Top-Level Counts', '| Area | Total Files | Code/Docs-ish Files | Notes |', '|---|---:|---:|---|']
for area in sorted(counts):
    inv_md.append(f"| {area} | {counts[area]['files']} | {counts[area]['code']} | |")
inv_md += ['', '## Core Focus Shortlist']
core = ['README.md']
core += [p['path'] + '/package.json' if p['path'] != '.' else 'package.json' for p in packages[:12]]
for item in core[:15]:
    inv_md.append(f'- `{item}`')
inv_md += ['', '## Exhaustive/Generated/Content-Heavy Areas']
for area, meta in sorted(counts.items(), key=lambda kv: kv[1]['code'], reverse=True)[:8]:
    if meta['code'] >= 100:
        inv_md.append(f'- `{area}/` — large area; likely sample first rather than exhaustively read')
if len(inv_md) < 30:
    inv_md.append('- No obviously huge areas detected by the bootstrap scan')
inv_md += ['', '## Full Inventory', 'See generated source list snapshot at analysis time:', f'- `{inv_file}`', '', 'Representative tree/filter excerpt:', '```text', tree_lines(entries, slug), '```', '', '## Seen / Not Yet Seen', '### Seen', '- Bootstrap inventory and package metadata scan completed', '- Top-level repo tree captured', '- Package manifests inventoried', '- Candidate import hotspots identified', '', '### Not Yet Seen / Deferred', '- Deep semantic review of most source files is still pending', '- Any area not explicitly read in later notes remains deferred', '', '## Notes', '- This file is the coverage guardrail: architectural conclusions should not pretend exhaustive review while major areas remain deferred.', '- For very large repos, explicit sampling is preferable to fake completeness.', '', '## Related', '- [[index]]', '- [[00b-dependency-map]]', '- [[01-system-map]]']
write_preserving_frontmatter(target / '00-file-inventory.md', '\n'.join(inv_md) + '\n')

# dependency markdown
pkg_graph_lines = []
for pkg in sorted(packages, key=lambda x: x['name']):
    pkg_graph_lines.append(pkg['name'])
    for dep in pkg['deps'][:12]:
        marker = ' (workspace)' if dep in package_names else ''
        pkg_graph_lines.append(f'  -> {dep}{marker}')

hotspot_lines = [f'- `{rel}` ({count} import/export edges)' for count, rel in hotspots[:12]] or ['- No import hotspots detected by bootstrap']

dep_md = []
dep_md += ['# 00b Dependency Map', '', '## Purpose', 'Make code-level and package-level dependencies explicit.', '', '## Coverage Link', '- Source inventory: `00-file-inventory.md`', '- Analysis status: bootstrap', '- Files/areas used for this dependency map: package manifests and a bootstrap import-count scan', '- Major deferred areas affecting this map: deep intra-module dependencies and semantic/runtime-only edges', '', '## Package Dependency Overview', '| Package/Module | Direct Depends On | Runtime Role | Risk Notes |', '|---|---|---|---|']
for pkg in sorted(packages, key=lambda x: x['name']):
    deps = ', '.join(pkg['deps'][:5] + (['...'] if len(pkg['deps']) > 5 else [])) or '—'
    dep_md.append(f"| `{pkg['name']}` | {deps} | | |")
dep_md += ['', '## Import/Relation Hotspots', *hotspot_lines, '', '## Package-Level Dependency Graph', '```text', *pkg_graph_lines[:200], '```', '', '## File/Module Import Graph', 'Bootstrap import-edge graph for top hotspot files:', '```text', *(file_graph_blocks or ['No import edges detected by bootstrap']), '```', '', 'Legend:', '- `A -> B` = import / dependency / call edge', '- `A => B` = writes / generates', '- `A ~> B` = runtime data/event flow', '', '## External Dependencies', '| Dependency | Where Used | Why It Exists | Replaceable? | Notes |', '|---|---|---|---|---|']
external = {}
for pkg in packages:
    for dep in pkg['deps']:
        if dep not in package_names:
            external.setdefault(dep, set()).add(pkg['name'])
for dep in sorted(external)[:40]:
    where = ', '.join(sorted(external[dep])[:3] + (['...'] if len(external[dep]) > 3 else []))
    dep_md.append(f'| `{dep}` | {where} | | | |')
dep_md += ['', '## Central Hubs', '- Highest import-count files from the bootstrap scan are the first candidates for central hubs', '- Cross-check with runtime/system map before declaring architectural centrality', '', '## Internal Coupling Notes', '- Bootstrap scan captures package dependencies and first-pass import edges, not full semantic coupling', '- Relative imports are partially resolved when file targets exist; aliases/dynamic imports may remain unresolved', '- Thin wrappers and true hubs still need human confirmation', '', '## Confidence', '- Coverage level for this dependency map: sampled', '- Highest-confidence dependency areas: package manifests, direct package dependencies, explicit static imports in hotspot files', '- Lowest-confidence dependency areas: deep file-to-file imports, aliased imports, dynamic/runtime-only relationships', '- Bootstrap-only claims still present: most runtime-role and coupling interpretation', '- Manual verification still needed for: true architectural hubs, dynamic imports, runtime-only edges', '', '## Related', '- [[index]]', '- [[00-file-inventory]]', '- [[01-system-map]]', '- [[02-runtime-model]]']
write_preserving_frontmatter(target / '00b-dependency-map.md', '\n'.join(dep_md) + '\n')

# system map bootstrap
component_rows = []
for pkg in sorted(packages, key=lambda x: x['path']):
    role = 'package'
    path_lower = pkg['path'].lower()
    if 'plugin' in path_lower:
        role = 'adapter/plugin'
    elif 'sdk' in path_lower:
        role = 'core package'
    elif 'observer' in path_lower or 'dashboard' in path_lower:
        role = 'ui/service'
    elif pkg['path'] in {'.', ''}:
        role = 'root package'
    notes_text = ''
    component_rows.append(f"| `{pkg['name']}` | `{pkg['path']}` | {role} | bootstrap-inferred | `package.json` | {notes_text} |")

system_graph = []
for pkg in sorted(packages, key=lambda x: x['name'])[:20]:
    system_graph.append(pkg['name'])
    for dep in pkg['deps'][:8]:
        marker = ' (workspace)' if dep in package_names else ''
        system_graph.append(f'  -> {dep}{marker}')

state_dirs = []
for candidate in ['.a5c', 'state', 'runs', 'logs', 'cache', '.github', 'scripts']:
    matches = [p for p in entries if p == candidate or p.startswith(candidate + '/')]
    if matches:
        state_dirs.append(f'- `{candidate}`')

sys_md = []
sys_md += ['# 01 System Map', '', '## Purpose', 'Describe the system at rest: what exists, where it lives, and what each major part is responsible for.', '', '## Coverage Link', '- Source inventory: `00-file-inventory.md`', '- Analysis status: bootstrap', '- Files/areas used for this map: package manifests, top-level tree, bootstrap dependency/import scan', '- Major deferred areas affecting this map: deep semantics of most source files and any large directories not yet manually reviewed', '', '## Repo Shape']
for area, meta in sorted(counts.items(), key=lambda kv: kv[1]['code'], reverse=True)[:8]:
    sys_md.append(f'- `{area}/` — {meta["code"]} code/docs-ish files')
sys_md += ['', '## Repo Tree', '```text', tree_lines(entries, slug), '```', '', '## Major Components', '| Component | Path | Type | Responsibility | Evidence | Notes |', '|---|---|---|---|---|---|']
sys_md += component_rows[:20] or ['| | | | | |']
sys_md += ['', '## File/Module Relationship Graph', '```text', *(system_graph[:160] or ['No package relationships detected by bootstrap']), '```', '', 'Use arrows like:', '- `A -> B` = imports/calls/depends on', '- `A => B` = generates/writes', '- `A ~> B` = runtime/event/data flow', '', '## Entrypoints', '- Start with package manifests (`package.json`) and top import hotspots from `00b-dependency-map.md`', '- Confirm actual CLI/server/library entrypoints during manual review', '', '## State and Storage']
sys_md += state_dirs or ['- No obvious state/storage dirs detected by bootstrap']
sys_md += ['', '## External Surfaces', '- Package manifests indicate external dependencies and possible CLI surfaces', '- Import hotspots indicate likely architecture hubs', '', '## Dependency Notes', '- See `00b-dependency-map.md` for bootstrap package/import dependency information', '', '## Open Questions', '- Which packages are true runtime cores vs thin wrappers?', '- Which entrypoints are authoritative?', '- Which large areas should be sampled first?', '', '## Related', '- [[index]]', '- [[00-file-inventory]]', '- [[00b-dependency-map]]', '- [[02-runtime-model]]', '- [[03-core-primitives]]']
system_map_path = target / '01-system-map.md'
if not should_preserve_enriched(system_map_path):
    write_preserving_frontmatter(system_map_path, '\n'.join(sys_md) + '\n')

# runtime model bootstrap
runtime_md = []
runtime_md += ['# 02 Runtime Model', '', '## Related', '- [[index]]', '- [[00b-dependency-map]]', '- [[01-system-map]]', '- [[03-core-primitives]]', '- [[05-redesign-v1]]', '', '## Purpose', 'Reconstruct how the system behaves over time.', '', '## Coverage Link', '- Source inventory: `00-file-inventory.md`', '- Analysis status: bootstrap', '- Files/areas used for this runtime model: package manifests, bootstrap dependency/import scan, system map bootstrap, top import hotspots', '- Major deferred areas affecting this model: actual execution/replay internals, dynamic runtime behavior, most non-hotspot files', '', '## Main Flow', '1. Bootstrap inference only: identify likely startup surfaces', '2. Bootstrap inference only: identify likely coordinators', '3. Bootstrap inference only: identify likely helpers/adapters', '4. Bootstrap inference only: identify likely trust/output boundaries', '5. Manual enrichment required before claiming real runtime reconstruction', '', 'Write the actual repo-specific flow here. If a step is inferred rather than verified, label it.', '', '## Control Flow', '- What starts a run/session? bootstrap inference only', '- What decides the next step? bootstrap inference only', '- What can interrupt flow? bootstrap inference only', '- What completes or aborts flow? bootstrap inference only', '', '## Data Flow', '- Inputs: inferred from package manifests/import surfaces', '- Internal state transitions: inferred from package/import relationships only at bootstrap stage', '- Outputs/artifacts: inferred until runtime files are read directly', '- External calls/providers: dependencies and host integrations from package manifests/import graph', '', '## Data Flow Charts', '### High-level Flow', '```text', '[bootstrap input surface]', '  -> [bootstrap coordinator guess]', '  -> [bootstrap helper/adapter guess]', '  -> [bootstrap output/trust boundary guess]', '```', '', '### Detailed Flow', '```text', '[entrypoint?] -> [hotspot module?] -> [imported helper?] -> [external boundary?]', '```', '', '## Main Functions / Methods and Usage', '| Function / Method | Location | Role in Flow | How It Is Used |', '|---|---|---|---|', '| bootstrap hotspot | bootstrap scan result | candidate coordinator | manual enrichment required |', '', '## Pseudocode Reconstruction', '### Main Runtime Path', '```text', '[startup?] -> [main coordinator?] -> [helpers/adapters?] -> [outputs?]', '```', '', '### Secondary / Edge Paths', '```text', '[input/event?] -> [handler?] -> [state change?] -> [side effect?]', '```', '', '## State Transitions', '| State | Trigger In | Trigger Out | Persisted? | Notes |', '|---|---|---|---|---|', '| bootstrap-inferred | package/entrypoint detected | manual validation needed | unknown | this file is a bootstrap model, not a verified replay trace |', '', '## Persistence Model', '- Confirm state and storage directories from `01-system-map.md` during manual review', '- Treat any persistence assumptions here as provisional until runtime files are read directly', '', '## Trust Boundaries', '- User input', '- Repo/workspace input', '- External dependency and host-tool boundaries', '- Generated outputs/state', '', '## Open Questions', '- Which detected entrypoints are the actual authoritative runtime entrypoints?', '- Which hotspot modules are true coordinators vs utility clusters?', '- Which state directories are runtime-critical vs incidental?', '', '## Confidence', '- Coverage level for this runtime reconstruction: sampled', '- Highest-confidence paths: top-level entry/dependency surfaces and hotspot import structure', '- Lowest-confidence paths: actual runtime sequencing, replay/iteration behavior, dynamic effects', '- Bootstrap-only claims still present: almost all flow sequencing until manual review happens', '- Manual verification still needed for: startup path, steady-state loop, persistence, error/exit behavior']
runtime_model_path = target / '02-runtime-model.md'
if not should_preserve_enriched(runtime_model_path):
    write_preserving_frontmatter(runtime_model_path, '\n'.join(runtime_md) + '\n')

# index touch-up
index = target / 'index.md'
if index.exists():
    text = index.read_text()
    text = text.replace('- [ ] 00-file-inventory.md', '- [x] 00-file-inventory.md')
    text = text.replace('- [ ] 00b-dependency-map.md', '- [x] 00b-dependency-map.md')
    text = text.replace('- [ ] 01-system-map.md', '- [x] 01-system-map.md')
    text = text.replace('- [ ] 02-runtime-model.md', '- [x] 02-runtime-model.md')
    if 'complete enough for purpose' not in text:
        text = text.replace('- Bootstrap status: not started', '- Bootstrap status: bootstrap generated')
    text = text.replace('- Major deferred areas:', '- Major deferred areas: see `00-file-inventory.md`')
    replacements = {
        '| `00-file-inventory.md` | yes | no | no | no | template created |': '| `00-file-inventory.md` | yes | yes | no | no | bootstrap inventory generated |',
        '| `00b-dependency-map.md` | yes | no | no | no | template created |': '| `00b-dependency-map.md` | yes | yes | no | no | bootstrap dependency map generated |',
        '| `01-system-map.md` | yes | no | no | no | template created |': '| `01-system-map.md` | yes | yes | no | no | bootstrap system map generated |',
        '| `02-runtime-model.md` | yes | no | no | no | template created |': '| `02-runtime-model.md` | yes | yes | no | no | bootstrap runtime model generated |',
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    if should_preserve_enriched(system_map_path):
        text = text.replace('| `01-system-map.md` | yes | yes | no | no | bootstrap system map generated |', '| `01-system-map.md` | yes | yes | yes | yes | preserved previously enriched system map |')
    if should_preserve_enriched(runtime_model_path):
        text = text.replace('| `02-runtime-model.md` | yes | yes | no | no | bootstrap runtime model generated |', '| `02-runtime-model.md` | yes | yes | yes | yes | preserved previously enriched runtime model |')
    for name in ['03-core-primitives.md', '04-risk-and-bloat.md', '05-redesign-v1.md']:
        p = target / name
        if should_preserve_distill(p):
            text = text.replace(f'- [ ] {name}', f'- [x] {name}')
    if should_preserve_distill(target / '03-core-primitives.md'):
        text = text.replace('| `03-core-primitives.md` | yes | no | no | no | template created |', '| `03-core-primitives.md` | yes | no | yes | yes | preserved previously enriched distillate |')
    if should_preserve_distill(target / '04-risk-and-bloat.md'):
        text = text.replace('| `04-risk-and-bloat.md` | yes | no | no | no | template created |', '| `04-risk-and-bloat.md` | yes | no | yes | yes | preserved previously enriched distillate |')
    if should_preserve_distill(target / '05-redesign-v1.md'):
        text = text.replace('| `05-redesign-v1.md` | yes | no | no | no | template created |', '| `05-redesign-v1.md` | yes | no | yes | yes | preserved previously enriched distillate |')
    lang_line = '- Languages: ' + (', '.join(f'{name} ({count})' for name, count in languages) if languages else 'none detected')
    framework_line = '- Frameworks / tooling: ' + (', '.join(framework_hits) if framework_hits else 'none detected')
    entry_line = '- Entrypoint candidates: ' + (', '.join(f'`{p}`' for p in entrypoint_candidates[:8]) if entrypoint_candidates else 'none detected')
    assist_line = '- Context assist notes: use detected stack only as a heuristic lens; verify from source before concluding'
    text = re.sub(r'^- Languages:.*$', lang_line, text, flags=re.M)
    text = re.sub(r'^- Frameworks / tooling:.*$', framework_line, text, flags=re.M)
    text = re.sub(r'^- Entrypoint candidates:.*$', entry_line, text, flags=re.M)
    text = re.sub(r'^- Context assist notes:.*$', assist_line, text, flags=re.M)
    text = re.sub(r'^- Major deferred areas: see `00-file-inventory\.md`.*$', '- Major deferred areas: see `00-file-inventory.md`', text, flags=re.M)
    # Always reconcile the method version to the canonical VERSION file.
    # Status fields (Current phase / Completion state / Next action) are intentionally
    # preserved — they describe human-judged enrichment state, not tool state.
    text = re.sub(r'^- Scanman method version: `[^`]*`.*$', f'- Scanman method version: `{scanman_version}`', text, flags=re.M)
    index.write_text(text)
PY

echo "Generated scanman bootstrap files:"
echo "  $TARGET_DIR/00-file-inventory.md"
echo "  $TARGET_DIR/00b-dependency-map.md"
echo "Inventory snapshot: $INV_FILE"
