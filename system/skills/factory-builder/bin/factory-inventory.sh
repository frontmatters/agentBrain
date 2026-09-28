#!/usr/bin/env bash
set -euo pipefail
# Resolve the vault through vault.sh rather than assuming a location. A user can
# move it with AGENTBRAIN_VAULT, and an install from before the rename still has
# local/ instead of vault/; both were invisible while this hardcoded a path.
#
# No fallback on purpose. A default guess here would report on a directory that
# may not be the user's vault, and an inventory that names the wrong source is
# worse than one that refuses: the reader has no way to tell the two apart.
_SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_VAULT_LIB="$_SELF_DIR/../../../../scripts/lib/vault.sh"
[ -f "$_VAULT_LIB" ] || { echo "factory-inventory: cannot find scripts/lib/vault.sh; run it from an agentBrain checkout" >&2; exit 2; }
# shellcheck source=/dev/null
. "$_VAULT_LIB"
VAULT="$(vault_dir)"
ROOT="$HOME/Developer"; OUT="$ROOT/factory-registry"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) echo 'usage: factory-inventory.sh [--root DEVELOPER_DIR] [--out OUTPUT_DIR]'; exit 0;;
    *) echo "error: unknown option: $1" >&2; exit 2;;
  esac
done
mkdir -p "$OUT"
python3 - "$ROOT" "$OUT" "$VAULT/projects" <<'PY'
import datetime, json, os, pathlib, re, subprocess, sys
root,out,brain=map(pathlib.Path,sys.argv[1:]); root=root.expanduser().resolve(); out=out.expanduser().resolve(); brain=brain.expanduser()
skip={'node_modules','.git','build','dist','target','DerivedData','vendor','__pycache__','.cache','_archive','_extern'}
def eligible(p):
    if any(x in skip for x in p.parts): return False
    if p.name.startswith('download-zips-tmp'): return False
    return p.is_dir()
def markers(p):
    names={x.name for x in p.iterdir()} if p.exists() else set()
    return [x for x in ('factory.json','package.json','Cargo.toml','Package.swift','pyproject.toml','project.godot','*.xcodeproj','*.xcworkspace','bin','src','native','plugin','extension','tests','test.sh') if (p/x).exists() if '*' not in x] + [x.name for x in p.glob('*.xcodeproj')]+[x.name for x in p.glob('*.xcworkspace')]
def tech(p):
    out=[]
    if (p/'package.json').exists(): out.append('node')
    if (p/'Cargo.toml').exists(): out.append('rust')
    if (p/'Package.swift').exists() or list(p.glob('*.xcodeproj')): out.append('swift/apple')
    if (p/'pyproject.toml').exists() or (p/'requirements.txt').exists(): out.append('python')
    if (p/'project.godot').exists(): out.append('godot')
    if list(p.glob('*.uproject')): out.append('unreal')
    if (p/'plugin').exists(): out.append('plugin')
    return out
def project_note(p):
    want=str(p)
    for f in brain.glob('*/index.md'):
        try: s=f.read_text(errors='ignore')
        except: continue
        if want in s or re.search(rf'(?m)^(?:slug|repo|path):\s*{re.escape(p.name)}\s*$',s,re.I): return f.parent.name
    return None
def hint(p,m,t):
    s=(p.name+' '+' '.join(m)+' '+' '.join(t)).lower(); h=[]
    if any(x in s for x in ('game','unity','godot','uproject')): h.append('game')
    if 'vst' in s or 'audio' in s or 'juce' in s: h.append('audio-plugin')
    if 'max4live' in s or 'max-for-live' in s or p.name.lower().startswith('ableton'): h.append('max-for-live-device')
    if 'extension' in s or 'browser' in s: h.append('extension')
    if 'xcode' in s or 'swift/apple' in t or 'tauri' in s: h.append('desktop-or-mobile-app')
    if 'bin' in m or 'cli' in s: h.append('cli')
    if 'factory.json' in m: h.append('registered-factory')
    return list(dict.fromkeys(h))
projects=[]
roots=[p for p in root.iterdir() if eligible(p)]
work=root/'_work'
if work.is_dir():
    roots += [p for area in work.iterdir() if eligible(area) for p in area.iterdir() if eligible(p)]
seen=set()
for p in sorted(roots):
    p=p.resolve()
    if str(p) in seen: continue
    seen.add(str(p)); m=markers(p); t=tech(p)
    if not (p/'.git').exists() and not m: continue
    f=(p/'factory.json').exists(); note=project_note(p)
    projects.append({'name':p.name,'path':str(p),'git':(p/'.git').exists(),'factoryJson':f,'projectNote':note,'technology':t,'evidence':m,'hints':hint(p,m,t),'review':'registered' if f else 'needs-review'})
report={'generated':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(root),'count':len(projects),'projects':projects}
(out/'projects.json').write_text(json.dumps(report,indent=2)+'\n')
md=['# Developer project inventory','',f"Generated: `{report['generated']}`",f"Projects detected: **{len(projects)}**",'', '| Project | Factory | Brain note | Technology | Hints |','|---|---|---|---|---|']
for x in projects:
 md.append(f"| `{x['name']}` | {'yes' if x['factoryJson'] else 'no'} | {x['projectNote'] or '-'} | {', '.join(x['technology']) or '-'} | {', '.join(x['hints']) or '-'} |")
(out/'projects-dashboard.md').write_text('\n'.join(md)+'\n')
print(out/'projects.json'); print(out/'projects-dashboard.md')
PY
