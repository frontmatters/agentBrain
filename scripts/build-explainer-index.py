#!/usr/bin/env python3
"""Build one searchable, tree-browsable HTML entrypoint over ALL explainers —
the main vault (local/explainers) plus every sealed space (local/spaces/*/explainers).

Space explainers are included in the data but gated behind an "include spaces"
toggle that defaults OFF (privacy): with it off they are hidden from the tree and
excluded from search. Output: local/explainers/index.html.

Run standalone: python3 scripts/build-explainer-index.py
Auto-run: invoked by brain-explain after every render.
"""
import re, json, os, pathlib, html as _html

ROOT = pathlib.Path(__file__).resolve().parent.parent
EX = ROOT / "local/explainers"
OUT = EX / "index.html"

def frontmatter(text):
    if not text.startswith("---\n"): return {}
    end = text.find("\n---\n", 4)
    if end == -1: return {}
    fm = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m: fm[m.group(1)] = m.group(2).strip()
    return fm

def title_desc(body):
    title = desc = ""
    for line in body.splitlines():
        s = line.strip()
        if not title and s.startswith("# "):
            title = s[2:].strip(); continue
        if title and s and s[0] not in "#:>|-" and not s.startswith("!["):
            desc = s; break
    desc = re.sub(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]", r"\1", desc)  # wikilinks
    desc = re.sub(r"[*`]", "", desc)                               # md marks
    return title, desc[:200]

# Locale detection is config-driven (not hardcoded): stopword sets per locale come
# from system/explainers/locales.json (framework default) merged with an optional
# local/explainers/locales.json (per-machine additions). Add a locale = edit config.
# A note's frontmatter `lang:` always overrides this heuristic.
_LOCALES = None
def _locales():
    global _LOCALES
    if _LOCALES is None:
        _LOCALES = {}
        for p in (ROOT / "system/explainers/locales.json", ROOT / "local/explainers/locales.json"):
            if p.exists():
                try:
                    for k, v in json.loads(p.read_text()).items():
                        if isinstance(v, list):
                            _LOCALES[k] = set(v)
                except Exception:
                    pass
        if not _LOCALES:  # built-in safety net if config missing
            _LOCALES = {"en": {"the", "a", "of", "and", "is", "to"},
                        "nl": {"de", "het", "een", "van", "en", "is"}}
    return _LOCALES

def detect_lang(text):
    words = set(re.findall(r"[a-zà-ÿ]+", text.lower()))
    best, best_n = "en", -1
    for loc, stop in _locales().items():
        n = len(words & stop)
        if n > best_n:
            best, best_n = loc, n
    return best

def scan(base, source):
    out = []
    if not base.exists(): return out
    for md in sorted(base.rglob("*.md")):
        txt = md.read_text(errors="ignore")
        fm = frontmatter(txt)
        if fm.get("type") != "explainer": continue
        body = txt[txt.find("\n---\n", 4) + 5:] if txt.startswith("---\n") else txt
        title, desc = title_desc(body)
        tags = fm.get("tags", "").lower()
        is_dd = ("deep-dive" in tags or "deep-dive" in (title or "").lower()
                 or "deep dive" in (title or "").lower())
        lang = fm.get("lang") or detect_lang((title or "") + " " + desc)
        html_file = md.with_suffix(".html")
        preview = md.parent / "preview.png"
        out.append({
            "title": title or md.stem,
            "desc": desc,
            "category": fm.get("category", "overig"),
            "source": source,
            "kind": "deep-dive" if is_dd else "explainer",
            "lang": lang,
            "href": os.path.relpath(html_file, EX),
            "preview": os.path.relpath(preview, EX) if preview.exists() else None,
            "rendered": html_file.exists(),
        })
    return out

items = scan(EX, "vault")
for sp in sorted((ROOT / "local/spaces").glob("*/explainers")):
    items += scan(sp, "space:" + sp.parent.name)

sources = sorted({it["source"] for it in items})
n_vault = sum(1 for it in items if it["source"] == "vault")
n_space = len(items) - n_vault

PAGE = r"""<!doctype html><html lang="nl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>agentBrain: Explainers</title>
<style>
:root{--bg:oklch(0.992 0.002 250);--ink:oklch(0.27 0.012 255);--soft:oklch(0.50 0.012 255);
--line:oklch(0.90 0.008 255);--accent:oklch(0.55 0.10 245);--hit:oklch(0.96 0.03 245);
--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.55}
.wrap{max-width:900px;margin:0 auto;padding:44px 0 80px}
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
.badge.sp{color:oklch(0.55 0.13 25)}
details.catgrp{border-top:1px solid var(--line)}
details.catgrp>summary{cursor:pointer;list-style:none;display:flex;align-items:center;gap:8px;
padding:9px 16px 9px 30px;font-size:11.5px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;
color:var(--soft);background:oklch(0.984 0.003 250)}
details.catgrp>summary::-webkit-details-marker{display:none}
details.catgrp>summary:hover{color:var(--ink)}
.chev2{font-size:9px;transition:transform .15s;display:inline-block}
details.catgrp[open]>summary .chev2{transform:rotate(90deg)}
.ccount{font-size:10px;font-weight:600;color:var(--soft);background:#fff;border:1px solid var(--line);border-radius:999px;padding:0 6px}
a.item{display:flex;gap:12px;align-items:flex-start;text-decoration:none;color:inherit;padding:10px 16px 10px 44px;border-top:1px solid var(--line)}
.thumb{width:104px;height:66px;object-fit:cover;object-position:top left;border:1px solid var(--line);border-radius:6px;flex:none;background:#fff}
.it-txt{min-width:0;flex:1}
a.item:hover{background:var(--hit)}
.it-t{font-weight:600;font-size:14.5px}.it-t mark{background:oklch(0.9 0.14 95);color:inherit;border-radius:2px}
.it-d{color:var(--soft);font-size:13px;margin-top:2px}.it-d mark{background:oklch(0.9 0.14 95);border-radius:2px}
.it-warn{color:oklch(0.6 0.13 25);font-size:11px;margin-left:6px}
.kind{font-size:10px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;margin-left:8px;color:var(--soft);vertical-align:1px}
.kind.dd{color:oklch(0.52 0.15 285)}
.lang-b{font-size:9px;font-weight:700;letter-spacing:.04em;margin-left:6px;color:var(--soft);border:1px solid var(--line);border-radius:3px;padding:0 4px;vertical-align:1px}
#empty{display:none;color:var(--soft);padding:30px 4px;text-align:center}
footer{margin-top:40px;padding-top:14px;border-top:1px solid var(--line);color:var(--soft);font-size:12px}
</style></head><body><div class="wrap">
<h1>Explainers</h1>
<p class="sub">One entrypoint across the vault and the spaces, browse as a tree, search live.</p>
<div class="bar">
<input id="q" type="search" placeholder="Search by title, description or category…" autocomplete="off">
<label class="tgl"><input type="checkbox" id="sp"> include spaces</label>
<span class="count" id="count"></span>
</div>
<div id="tree"></div>
<div id="empty">No explainers found.</div>
<footer>__FOOTER__</footer>
</div>
<script>
const DATA = __DATA__;
const tree=document.getElementById('tree'), q=document.getElementById('q'),
      sp=document.getElementById('sp'), empty=document.getElementById('empty'),
      count=document.getElementById('count');
function el(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e;}
function addHL(parent,s,t){ // append text with <mark> around the match — DOM only, no innerHTML
  if(!t){parent.appendChild(document.createTextNode(s));return;}
  const i=s.toLowerCase().indexOf(t);
  if(i<0){parent.appendChild(document.createTextNode(s));return;}
  parent.appendChild(document.createTextNode(s.slice(0,i)));
  parent.appendChild(el('mark',null,s.slice(i,i+t.length)));
  parent.appendChild(document.createTextNode(s.slice(i+t.length)));
}
function render(){
  const t=q.value.trim().toLowerCase(), spaces=sp.checked;
  const base=DATA.filter(d=>spaces||d.source==='vault');
  const items=t?base.filter(d=>(d.title+' '+d.desc+' '+d.category).toLowerCase().includes(t)):base;
  count.textContent=items.length+' / '+base.length;
  tree.textContent=''; empty.style.display=items.length?'none':'block';
  const bySrc={}; for(const d of items){(bySrc[d.source]=bySrc[d.source]||[]).push(d);}
  const order=Object.keys(bySrc).sort((a,b)=>(a!=='vault')-(b!=='vault')||a.localeCompare(b));
  for(const src of order){
    const list=bySrc[src], isSp=src!=='vault';
    const det=el('details','grp'); det.open=!!t; // collapsed by default (tree); auto-open on search
    const sum=el('summary'); sum.appendChild(el('span','chev','▸'));
    sum.appendChild(document.createTextNode(src==='vault'?'Vault':src.replace('space:','space · ')));
    sum.appendChild(el('span','badge'+(isSp?' sp':''),String(list.length)));
    det.appendChild(sum);
    const byCat={}; for(const d of list){(byCat[d.category]=byCat[d.category]||[]).push(d);}
    for(const cat of Object.keys(byCat).sort()){
      const cd=el('details','catgrp'); cd.open=!!t; // collapsible subcategory
      const cs=el('summary','catsum'); cs.appendChild(el('span','chev2','▸'));
      cs.appendChild(document.createTextNode(cat));
      cs.appendChild(el('span','ccount',String(byCat[cat].length)));
      cd.appendChild(cs);
      for(const d of byCat[cat].sort((a,b)=>a.title.localeCompare(b.title))){
        const a=el('a','item'); a.setAttribute('href',d.href);
        if(d.preview){const im=el('img','thumb');im.setAttribute('src',d.preview);im.setAttribute('loading','lazy');im.setAttribute('alt','');a.appendChild(im);}
        const txt=el('div','it-txt');
        const tt=el('div','it-t'); addHL(tt,d.title,t);
        tt.appendChild(el('span','kind'+(d.kind==='deep-dive'?' dd':''),d.kind));
        tt.appendChild(el('span','lang-b',(d.lang||'').toUpperCase()));
        if(!d.rendered) tt.appendChild(el('span','it-warn','not rendered'));
        txt.appendChild(tt);
        if(d.desc){const dd=el('div','it-d'); addHL(dd,d.desc,t); txt.appendChild(dd);}
        a.appendChild(txt);
        cd.appendChild(a);
      }
      det.appendChild(cd);
    }
    tree.appendChild(det);
  }
}
q.addEventListener('input',render); sp.addEventListener('change',render); render();
</script></body></html>"""

footer = f"{len(items)} explainers · {n_vault} vault · {n_space} in spaces ({len(sources)-1 if n_space else 0}). Auto-generated by build-explainer-index.py."
out = (PAGE.replace("__DATA__", json.dumps(items, ensure_ascii=False))
           .replace("__FOOTER__", _html.escape(footer)))
OUT.write_text(out)
print(f"explainer-index: {len(items)} items ({n_vault} vault + {n_space} spaces) -> {OUT.relative_to(ROOT)}")
