#!/usr/bin/env python3
"""Build one searchable, tree-browsable HTML map of the developer ecosystem —
same tree+search UX as the explainer index, but over projects.

Input : local/ecosystem/projects.json  (array of profiled projects:
        {name, what, domain, status, active, last_commit, tech, relations})
Output: local/ecosystem/index.html

Tree: domain (level 1) -> status (level 2, collapsible) -> project (level 3).
An "active only" toggle (default off) filters to active projects; live search
across name/what/tech/domain/status. English UI (agentBrain is EN-primary).
"""
import json, os, pathlib, html as _html

ROOT = pathlib.Path(__file__).resolve().parent.parent
ECO = ROOT / "local/ecosystem"
DATA = ECO / "projects.json"
OUT = ECO / "index.html"

items = json.loads(DATA.read_text()) if DATA.exists() else []
for it in items:  # all live under ~/Developer/<name> — derive a pasteable path
    it.setdefault("path", "~/Developer/" + it.get("name", ""))
n_active = sum(1 for it in items if it.get("active"))
domains = sorted({it.get("domain", "other") for it in items})

PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Developer Ecosystem — Map</title>
<style>
:root{--bg:oklch(0.992 0.002 250);--ink:oklch(0.27 0.012 255);--soft:oklch(0.50 0.012 255);
--line:oklch(0.90 0.008 255);--accent:oklch(0.55 0.10 245);--hit:oklch(0.96 0.03 245);
--ok:oklch(0.58 0.13 150);--warn:oklch(0.6 0.13 55);--dim:oklch(0.6 0.02 255);
--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.55}
.wrap{max-width:960px;margin:0 auto;padding:44px 0 80px}
h1{font-size:30px;font-weight:680;letter-spacing:-0.02em;margin:0 0 4px}
.sub{color:var(--soft);margin:0 0 22px;font-size:14px}
.bar{position:sticky;top:0;background:var(--bg);padding:12px 0;border-bottom:1px solid var(--line);z-index:5;
display:flex;gap:14px;align-items:center;flex-wrap:wrap}
#q{flex:1;min-width:220px;padding:9px 13px;border:1px solid var(--line);border-radius:8px;font:inherit;background:#fff;color:var(--ink)}
#q:focus{outline:none;border-color:var(--accent)}
.tgl{display:flex;align-items:center;gap:7px;font-size:13px;color:var(--soft);cursor:pointer;user-select:none}
.count{font-size:12px;color:var(--soft)}
details.grp{margin:18px 0 0;border:1px solid var(--line);border-radius:10px;overflow:hidden}
details.grp>summary{cursor:pointer;list-style:none;padding:12px 16px;font-weight:640;font-size:15px;
display:flex;align-items:center;gap:9px;background:oklch(0.975 0.004 250)}
details.grp>summary::-webkit-details-marker{display:none}
.chev{transition:transform .15s;color:var(--soft)}details[open]>summary .chev{transform:rotate(90deg)}
.badge{font-size:11px;font-weight:600;color:var(--accent);border:1px solid var(--line);border-radius:999px;padding:1px 8px;background:#fff}
details.catgrp{border-top:1px solid var(--line)}
details.catgrp>summary{cursor:pointer;list-style:none;display:flex;align-items:center;gap:8px;
padding:9px 16px 9px 30px;font-size:11.5px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;
color:var(--soft);background:oklch(0.984 0.003 250)}
details.catgrp>summary::-webkit-details-marker{display:none}
.chev2{font-size:9px;transition:transform .15s;display:inline-block}
details.catgrp[open]>summary .chev2{transform:rotate(90deg)}
.ccount{font-size:10px;font-weight:600;color:var(--soft);background:#fff;border:1px solid var(--line);border-radius:999px;padding:0 6px}
.row{display:block;padding:10px 16px 10px 44px;border-top:1px solid var(--line)}
.row:hover{background:var(--hit)}
.r-t{font-weight:600;font-size:14.5px}.r-t mark{background:oklch(0.9 0.14 95);border-radius:2px}
.r-d{color:var(--soft);font-size:13px;margin-top:2px}.r-d mark{background:oklch(0.9 0.14 95);border-radius:2px}
.st{font-size:9.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;margin-left:8px;padding:0 5px;border-radius:3px;border:1px solid var(--line);vertical-align:1px;color:var(--soft)}
.st.active{color:#fff;background:var(--ok);border-color:var(--ok)}
.st.pending{color:var(--warn);border-color:var(--warn)}
.st.vendored{color:var(--dim)}
.meta{color:var(--soft);font-size:12px;margin-left:8px}
.copy{margin-left:8px;font-size:11px;line-height:1.4;border:1px solid var(--line);background:#fff;color:var(--soft);border-radius:4px;padding:0 6px;cursor:pointer;vertical-align:1px}
.copy:hover{color:var(--ink);border-color:var(--accent)}
.tech{color:var(--soft);font-size:12px}
#empty{display:none;color:var(--soft);padding:30px 4px;text-align:center}
footer{margin-top:40px;padding-top:14px;border-top:1px solid var(--line);color:var(--soft);font-size:12px}
</style></head><body><div class="wrap">
<h1>Developer Ecosystem — Map</h1>
<p class="sub">Every project across ~/Developer — grouped by domain, active vs. inactive called out. Browse as a tree, search live.</p>
<div class="bar">
<input id="q" type="search" placeholder="Search by name, description, tech or domain…" autocomplete="off">
<label class="tgl"><input type="checkbox" id="act"> active only</label>
<span class="count" id="count"></span>
</div>
<div id="tree"></div>
<div id="empty">No projects found.</div>
<footer>__FOOTER__</footer>
</div>
<script>
const DATA = __DATA__;
const STATUS_ORDER = {active:0, pending:1, inactive:2, parked:3, archived:4, vendored:5};
const tree=document.getElementById('tree'), q=document.getElementById('q'),
      act=document.getElementById('act'), empty=document.getElementById('empty'),
      count=document.getElementById('count');
function el(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e;}
function addHL(parent,s,t){
  if(!t){parent.appendChild(document.createTextNode(s));return;}
  const i=s.toLowerCase().indexOf(t);
  if(i<0){parent.appendChild(document.createTextNode(s));return;}
  parent.appendChild(document.createTextNode(s.slice(0,i)));
  parent.appendChild(el('mark',null,s.slice(i,i+t.length)));
  parent.appendChild(document.createTextNode(s.slice(i+t.length)));
}
function render(){
  const t=q.value.trim().toLowerCase(), activeOnly=act.checked;
  const base=DATA.filter(d=>!activeOnly||d.active);
  const items=t?base.filter(d=>((d.name||'')+' '+(d.what||'')+' '+(d.tech||'')+' '+(d.domain||'')+' '+(d.status||'')).toLowerCase().includes(t)):base;
  count.textContent=items.length+' / '+base.length+' · '+DATA.filter(d=>d.active).length+' active';
  tree.textContent=''; empty.style.display=items.length?'none':'block';
  const byDom={}; for(const d of items){(byDom[d.domain||'other']=byDom[d.domain||'other']||[]).push(d);}
  const order=Object.keys(byDom).sort((a,b)=>byDom[b].length-byDom[a].length||a.localeCompare(b));
  for(const dom of order){
    const list=byDom[dom];
    const det=el('details','grp'); det.open=!!t||order.length<=3;
    const sum=el('summary'); sum.appendChild(el('span','chev','▸'));
    sum.appendChild(document.createTextNode(dom));
    sum.appendChild(el('span','badge',String(list.length)));
    const na=list.filter(d=>d.active).length; if(na) sum.appendChild(el('span','meta',na+' active'));
    det.appendChild(sum);
    const bySt={}; for(const d of list){(bySt[d.status||'inactive']=bySt[d.status||'inactive']||[]).push(d);}
    const sts=Object.keys(bySt).sort((a,b)=>(STATUS_ORDER[a]??9)-(STATUS_ORDER[b]??9));
    for(const st of sts){
      const cd=el('details','catgrp'); cd.open=!!t||st==='active';
      const cs=el('summary','catsum'); cs.appendChild(el('span','chev2','▸'));
      cs.appendChild(document.createTextNode(st));
      cs.appendChild(el('span','ccount',String(bySt[st].length)));
      cd.appendChild(cs);
      for(const d of bySt[st].sort((a,b)=>(a.name||'').localeCompare(b.name||''))){
        const row=el('div','row');
        const tt=el('div','r-t'); addHL(tt,d.name||'?',t);
        const stcls='st'+(d.status==='active'?' active':d.status==='pending'?' pending':d.status==='vendored'?' vendored':'');
        tt.appendChild(el('span',stcls,d.status||'?'));
        if(d.last_commit) tt.appendChild(el('span','meta',d.last_commit));
        const cp=el('button','copy','⧉'); cp.title='Copy path ('+(d.path||d.name)+')';
        cp.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();
          navigator.clipboard.writeText(d.path||d.name||'').then(()=>{cp.textContent='✓';setTimeout(()=>{cp.textContent='⧉';},900);});});
        tt.appendChild(cp);
        row.appendChild(tt);
        const dd=el('div','r-d'); addHL(dd,d.what||'',t);
        if(d.tech){dd.appendChild(document.createTextNode('  ')); dd.appendChild(el('span','tech','· '+d.tech));}
        row.appendChild(dd);
        cd.appendChild(row);
      }
      det.appendChild(cd);
    }
    tree.appendChild(det);
  }
}
q.addEventListener('input',render); act.addEventListener('change',render); render();
</script></body></html>"""

footer = f"{len(items)} projects · {n_active} active · {len(domains)} domains. Auto-generated by build-ecosystem-index.py."
out = (PAGE.replace("__DATA__", json.dumps(items, ensure_ascii=False))
           .replace("__FOOTER__", _html.escape(footer)))
ECO.mkdir(parents=True, exist_ok=True)
OUT.write_text(out)
print(f"ecosystem-index: {len(items)} projects ({n_active} active, {len(domains)} domains) -> {OUT.relative_to(ROOT)}")
