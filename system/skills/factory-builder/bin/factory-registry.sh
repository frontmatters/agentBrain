#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/Developer"
OUT="$ROOT/factory-registry"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) echo 'usage: factory-registry.sh [--root DEVELOPER_DIR] [--out OUTPUT_DIR]'; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"
python3 - "$ROOT" "$OUT" "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/factory-obeya.sh" "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/factory-profile.py" <<'PY'
import datetime, json, os, pathlib, subprocess, sys
root, out, obeya_bin, profile_bin = map(pathlib.Path, sys.argv[1:])
root = root.expanduser().resolve(); out = out.expanduser().resolve()
rows=[]
layout=json.loads((obeya_bin.parent.parent/'layout.json').read_text())
import importlib.util
_spec = importlib.util.spec_from_file_location("factory_discover", obeya_bin.parent / "factory-discover.py")
_disc = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_disc)
def factories():
    return _disc.factories(root)
for config in factories():
    factory=config.parent
    normalized=subprocess.run(['python3',str(profile_bin),str(factory)],capture_output=True,text=True)
    if normalized.returncode:
        rows.append({'path':str(factory),'project':factory.name,'status':'invalid',
                     'issues':[normalized.stderr.strip()]}); continue
    data=json.loads(normalized.stdout); lanes=data['lanes']; issues=[]; lane_rows={}
    for name in ('dev','next','live'):
        raw=lanes[name]; path=pathlib.Path(raw) if raw else None
        exists=bool(path and path.is_dir()); clean=None; sha=None
        if exists:
            try:
                sha=subprocess.check_output(['git','-C',str(path),'rev-parse','--short','HEAD'],text=True,stderr=subprocess.DEVNULL).strip()
                clean=not bool(subprocess.check_output(['git','-C',str(path),'status','--porcelain'],text=True,stderr=subprocess.DEVNULL).strip())
            except Exception: issues.append(f'{name} is not a readable git worktree')
        else: issues.append(f'missing {name} lane')
        lane_rows[name]={'path':str(path) if path else None,'exists':exists,'clean':clean,'sha':sha}
        if name in ('next','live') and clean is False: issues.append(f'{name} is dirty')
    for required in ('factory.json','README.md','R&D'):
        if not (factory/required).exists(): issues.append(f'missing {required}')
    if not data['releases'] or not pathlib.Path(data['releases']).is_dir():
        issues.append('missing releases')
    try:
        ob=json.loads(subprocess.run(['bash',str(obeya_bin),'--factory',str(factory),'--json'],capture_output=True,text=True,timeout=300).stdout)
    except Exception:
        ob=None
    status='ok' if not issues else 'attention'
    andon=(ob or {}).get('andon')
    rows.append({'project':data.get('project') or factory.name,'profile':data['profile'],'path':str(factory),'status':status,'issues':issues,'lanes':lane_rows,
                 'andon':andon,'next':(ob or {}).get('next')})
report={'generated':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(root),'factories':rows}
(out/'factories.json').write_text(json.dumps(report,indent=2)+'\n')
md=['# Factory registry','',f"Generated: `{report['generated']}`",'', '| Factory | Status | Dev | Next | Live | Andon | Next step | Issues |','|---|---|---|---|---|---|---|---|']
for r in rows:
    def lane(n):
        # plain words, no symbols: the sha, and what is wrong with the lane
        x=r.get('lanes',{}).get(n,{})
        if not x.get('exists'): return 'missing'
        return (x.get('sha') or '?') + (' dirty' if x.get('clean') is False else '')
    issues='; '.join(r.get('issues',[])) or 'none'
    a=r.get('andon')
    andon='no andon' if a is None else (f"{a['stopped']} stopped" + (f", oldest {a['oldestDays']}d" if a.get('oldestDays') is not None else '') + (f", {a['stale']} stale" if a.get('stale') else '') + (f", {a['undated']} undated" if a.get('undated') else '')) if a['stopped'] else 'clear'
    nxt=(r.get('next') or '-').replace('|','\\|')
    md.append(f"| `{r['project']}` | **{r['status']}** | {lane('dev')} | {lane('next')} | {lane('live')} | {andon} | {nxt} | {issues} |")
(out/'dashboard.md').write_text('\n'.join(md)+'\n')
print(out/'factories.json'); print(out/'dashboard.md')
PY
