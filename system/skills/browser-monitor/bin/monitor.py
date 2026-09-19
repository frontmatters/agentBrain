#!/usr/bin/env python3
"""Watch the owner work in a browser and record what breaks.

Opens a visible browser, navigates once, and then only listens: failed requests with
the server's answer, JavaScript exceptions, the payload of saves worth watching, and
the state of one element as it changes. Writes a report on stop.

Observe, never steer: after the first navigation this process must not click, type or
navigate. A cursor that moves on its own while someone demonstrates a bug destroys the
evidence.
"""
import argparse, json, os, re, signal, sys, time
from collections import Counter
from datetime import datetime


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url', help='page to open once at the start')
    p.add_argument('--log', required=True, help='log file; the report lands beside it as .md')
    p.add_argument('--watch', action='append', default=[],
                   help='TAG:path.to.value, polls one element and logs it when it changes')
    p.add_argument('--api-filter', default='',
                   help='comma-separated url fragments whose POST/PUT/PATCH payloads to record')
    p.add_argument('--width', type=int, default=1440)
    p.add_argument('--height', type=int, default=900)
    p.add_argument('--stop', action='store_true', help='stop a running monitor and write the report')
    return p.parse_args()


def log_line(path, kind, text):
    with open(path, 'a') as f:
        f.write(f"{datetime.now():%H:%M:%S}  {kind:<9} {text}\n")
        f.flush()


DEEP_WALK = """const w=(r,d=0,a=[])=>{ if(d>14||!r||!r.querySelectorAll) return a;
  for(const e of r.querySelectorAll('*')){a.push(e); if(e.shadowRoot) w(e.shadowRoot,d+1,a);} return a;};"""


def watch_script(specs):
    """One evaluate that reads every --watch target, so a slow page costs one round trip."""
    delen = []
    for spec in specs:
        tag, _, pad = spec.partition(':')
        delen.append(
            f"(() => {{ const el=w(document).find(e=>e.tagName==='{tag.upper()}');"
            f" if(!el) return null; try {{ let v=el; for(const k of {json.dumps(pad.split('.'))}) v=v?.[k];"
            f" return {json.dumps(spec)}+' = '+(Array.isArray(v)?v.length+' ('+v.map(x=>x&&(x.naam??x.name??x.id)||'(leeg)').join(', ')+')':JSON.stringify(v)); }}"
            f" catch(e) {{ return {json.dumps(spec)}+' = (niet leesbaar)'; }} }})()"
        )
    return "() => { %s return [%s].filter(Boolean); }" % (DEEP_WALK, ', '.join(delen))


def write_report(log_path):
    """A report for a reader who was not there."""
    md = os.path.splitext(log_path)[0] + '.md'
    if not os.path.exists(log_path):
        return None
    regels = open(log_path).read().splitlines()
    soorten = Counter(r.split()[1] for r in regels if len(r.split()) > 1)
    fouten = [r for r in regels if re.search(r'\b(FOUT|JS-FOUT|LEEG)\b', r)]
    paginas = [r.split('pagina')[-1].strip() for r in regels if ' pagina ' in r]
    standen = [r for r in regels if ' stand ' in r]
    with open(md, 'w') as f:
        f.write(f"# Meekijk-sessie {datetime.now():%Y-%m-%d %H:%M}\n\n")
        f.write(f"Log: `{log_path}`, {len(regels)} regels.\n\n")
        f.write("## Wat er bekeken is\n\n")
        for pad in dict.fromkeys(paginas):
            f.write(f"- `{pad}`\n")
        f.write(f"\n## Wat er misging ({len(fouten)})\n\n")
        if not fouten:
            f.write("Niets. Geen mislukte verzoeken, geen uitzonderingen.\n")
        for r in fouten:
            f.write(f"- `{r}`\n")
        f.write("\n## Verloop\n\n```\n")
        for r in regels[-60:]:
            f.write(r + "\n")
        f.write("```\n\n## Nog onverklaard\n\n")
        f.write("_Vul in wat het log niet verklaart. Een open vraag is bruikbaarder "
                "voor de volgende lezer dan een gok die als diagnose is opgeschreven._\n")
        f.write(f"\n---\nsoorten regels: {dict(soorten)}\n")
    return md


def main():
    a = parse_args()
    if a.stop:
        pidfile = a.log + '.pid'
        if os.path.exists(pidfile):
            pid = int(open(pidfile).read().strip())
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.remove(pidfile)
        md = write_report(a.log)
        print(f"gestopt; rapport: {md}")
        return

    os.makedirs(os.path.dirname(os.path.abspath(a.log)) or '.', exist_ok=True)
    open(a.log + '.pid', 'w').write(str(os.getpid()))
    filters = [x.strip() for x in a.api_filter.split(',') if x.strip()]

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False,
                              args=['--window-position=40,30', f'--window-size={a.width + 60},{a.height + 100}'])
        pg = b.new_page(viewport={'width': a.width, 'height': a.height})

        def op_verzoek(r):
            if r.method in ('PUT', 'POST', 'PATCH') and any(f in r.url for f in filters):
                kort = r.url.split('/api/')[-1][:60]
                body = r.post_data
                if body is None:
                    log_line(a.log, 'LEEG', f"{r.method} {kort}: GEEN BODY")
                    return
                try:
                    d = json.loads(body)
                    tel = next((len(v) for v in d.values() if isinstance(v, list)), None) if isinstance(d, dict) else None
                    log_line(a.log, 'opslag', f"{r.method} {kort}: " + (f"{tel} regel(s)" if tel is not None else f"{body[:70]}"))
                except Exception:
                    log_line(a.log, 'opslag', f"{r.method} {kort}: {body[:70]}")

        def op_antwoord(r):
            if r.status >= 400 and '/api/' in r.url:
                try:
                    uitleg = ' ' + r.text()[:110]
                except Exception:
                    uitleg = ''
                log_line(a.log, 'FOUT', f"{r.status} {r.request.method} {r.url.split('/api/')[-1][:52]}{uitleg}")

        pg.on('request', op_verzoek)
        pg.on('response', op_antwoord)
        pg.on('console', lambda m: log_line(a.log, 'console', m.text[:150]) if m.type == 'error' else None)
        pg.on('pageerror', lambda e: log_line(a.log, 'JS-FOUT', str(e).replace('\n', ' | ')[:400]))
        pg.on('framenavigated',
              lambda fr: log_line(a.log, 'pagina', fr.url) if fr == pg.main_frame else None)

        if a.url:
            pg.goto(a.url, wait_until='networkidle')
        log_line(a.log, 'start', 'meekijken begonnen: observeren, niet sturen')

        script = watch_script(a.watch) if a.watch else None
        vorige = None
        try:
            while True:
                if script:
                    try:
                        nu = pg.evaluate(script)
                        if nu and nu != vorige:
                            for regel in nu:
                                log_line(a.log, 'stand', regel)
                            vorige = nu
                    except Exception:
                        pass
                time.sleep(4)
        except KeyboardInterrupt:
            pass
        finally:
            log_line(a.log, 'einde', 'meekijken gestopt')
            write_report(a.log)
            b.close()


if __name__ == '__main__':
    main()
