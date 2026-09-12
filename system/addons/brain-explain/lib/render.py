#!/usr/bin/env python3
"""brain-explain renderer: markdown + shortcodes -> semantic HTML."""
import html, re, sys, pathlib

SHORTCODES = {  # name -> (container_class, item_class or None)
    "layers": ("layers", "layer"),
    "cards":  ("cards", "card"),
    "flow":   ("flow", "step"),
    "callout":("pull", None),
}

def split_frontmatter(text):
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            return text[end + 5:]
    return text

# Emoji/symbol -> inline SVG icons. House rule: SVG icons, never emoji. Every
# explainer inherits this — authors can keep typing ⚠/✅/❌ in markdown and get
# consistent, theme-coloured (currentColor) glyphs. Stroke-based, 1em, sized
# inline so it works in every theme without extra CSS. Arrows (→ ← ›) are
# typographic glyphs, not emoji — left untouched on purpose.
_ICON = (
    '<svg class="ex-icon ex-icon--{cls}" width="1em" height="1em" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" '
    'style="vertical-align:-0.14em;margin:0 0.06em">{path}</svg>'
)
ICONS = {
    "⚠": _ICON.format(cls="warn", path='<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>'),
    "✅": _ICON.format(cls="ok", path='<polyline points="20 6 9 17 4 12"/>'),
    "✔": _ICON.format(cls="ok", path='<polyline points="20 6 9 17 4 12"/>'),
    "✓": _ICON.format(cls="ok", path='<polyline points="20 6 9 17 4 12"/>'),
    "❌": _ICON.format(cls="no", path='<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'),
    "✗": _ICON.format(cls="no", path='<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'),
    "✕": _ICON.format(cls="no", path='<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'),
    # empty/not-granted marker (matrix counterpart to ✅) — outlined square
    "⬜": _ICON.format(cls="empty", path='<rect x="4" y="4" width="16" height="16" rx="2"/>'),
    "⬛": _ICON.format(cls="filled", path='<rect x="4" y="4" width="16" height="16" rx="2" fill="currentColor"/>'),
    # eye (viewer/read)
    "👁": _ICON.format(cls="eye", path='<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>'),
    # lock (managed/secured)
    "🔒": _ICON.format(cls="lock", path='<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>'),
    # key (credential/auth)
    "🔑": _ICON.format(cls="key", path='<circle cx="8" cy="15" r="4"/><path d="m10.5 12.5 6-6"/><path d="m17 8 2 2"/><path d="m14 11 2 2"/>'),
}
_ICON_RE = re.compile("(" + "|".join(re.escape(k) for k in ICONS) + ")️?")


def inline(s):
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\[\[([^\]]+)\]\]", r'<a class="wikilink" href="#">\1</a>', s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    # Emoji -> SVG last, so the <svg> markup isn't escaped or re-parsed.
    s = _ICON_RE.sub(lambda m: ICONS[m.group(1)], s)
    return s

def _parse_attrs(s):
    """Parse `key="value"` pairs from a shortcode attr string (e.g. title="X")."""
    return dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', s or ""))

def _render_body(body_lines):
    """Render a callout/blockquote body preserving bullet lists and paragraphs
    instead of flattening everything into one run-on line. A leading `**Title**`
    line becomes a bold lead paragraph on its own."""
    parts, bullets, para = [], [], []
    def flush_para():
        if para:
            parts.append("<p>" + inline(" ".join(para)) + "</p>"); para.clear()
    def flush_bullets():
        if bullets:
            parts.append("<ul>" + "".join(f"<li>{inline(b)}</li>" for b in bullets) + "</ul>"); bullets.clear()
    for l in body_lines:
        s = l.strip()
        if not s:
            flush_para(); flush_bullets(); continue
        if s.startswith("- "):
            flush_para(); bullets.append(s[2:].strip())
        else:
            flush_bullets(); para.append(s)
    flush_para(); flush_bullets()
    return "".join(parts)

def render_shortcode(name, body_lines, attrs=None):
    attrs = attrs or {}
    container, item = SHORTCODES.get(name, (None, None))
    title = attrs.get("title")
    title_html = f'<p class="callout-title"><strong>{inline(title)}</strong></p>' if title else ""
    if container is None:  # unknown -> safe blockquote degradation (structured)
        return f"<blockquote>{title_html}{_render_body(body_lines)}</blockquote>"
    if item is None:       # single-block (callout/pull) — structured body + optional title
        return f'<blockquote class="{container}">{title_html}{_render_body(body_lines)}</blockquote>'
    # A list item may wrap. Taking only the lines that start with "- " drops every
    # continuation line without a word, so a card silently renders half of what the
    # source says. Join wrapped lines onto the item they belong to instead.
    items = []
    for l in body_lines:
        st = l.strip()
        if st.startswith("- "):
            items.append(re.sub(r"^- +", "", st).strip())
        elif st and items:
            items[-1] = (items[-1] + " " + st).strip()
    cells = []
    for it in items:
        m = re.match(r"\*\*([^*]+)\*\*\s*[—-]\s*(.*)", it)
        if m:
            cells.append(f'<div class="{item}"><h3>{inline(m.group(1))}</h3><p>{inline(m.group(2))}</p></div>')
        else:
            cells.append(f'<div class="{item}"><p>{inline(it)}</p></div>')
    return f'<div class="{container}">' + "".join(cells) + "</div>"

def _table_row(line):
    s = line.strip()
    if s.startswith("|"): s = s[1:]
    if s.endswith("|"): s = s[:-1]
    return [c.strip() for c in s.split("|")]

def _is_table_sep(line):
    s = line.strip()
    return "|" in s and "-" in s and re.fullmatch(r"[\s|:-]+", s) is not None

# Deep-dive 5-question loop: a paragraph led by **What**/**Why**/**Where**/
# **How**/**When** labels renders as a definition list, not a run-on block, so
# each answer is legible on its own. Matches "**What.**" and "**What** —" forms.
_LOOP_SPLIT = re.compile(r"\*\*(What|Why|Where|How|When)\.?\*\*\s*[—\-.:]?\s*")

def _slugify(text):
    t = re.sub(r"`([^`]+)`", r"\1", text)              # code
    t = re.sub(r"\*\*([^*]+)\*\*", r"\1", t)           # bold
    t = re.sub(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]", r"\1", t)  # wikilink
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)     # md link
    t = t.lower().strip()
    t = re.sub(r"[^\w\s-]", "", t)
    t = re.sub(r"[\s_]+", "-", t).strip("-")
    return t or "section"

def _para_html(text, cls):
    # Render the 5-question loop as a <dl> when present; else a normal paragraph.
    parts = _LOOP_SPLIT.split(text)
    labels, segs = parts[1::2], parts[2::2]
    # One label is enough. Requiring two meant both had to sit in the SAME
    # paragraph block, and every author puts a blank line between them, exactly as
    # the deep-dive skill shows. Measured on 2026-09-06: 37 explainers write
    # "**What.**" and 4 produced a definition list. The feature existed, was
    # documented as the expected rendering, and fired for one document in nine.
    if len(labels) >= 1:
        pre = parts[0].strip()
        pre_html = f"<p>{inline(pre)}</p>" if pre else ""
        items = "".join(
            f'<dt style="font-weight:600;margin-top:0.55em">{lbl}</dt>'
            f'<dd style="margin:0.15em 0 0 0">{inline(seg.strip())}</dd>'
            for lbl, seg in zip(labels, segs))
        return pre_html + f'<dl class="qloop" style="margin:0.5em 0">{items}</dl>'
    return f"<p{cls}>" + inline(text) + "</p>"

def parse_body(md):
    out, i, lines = [], 0, md.split("\n")
    seen_slugs = {}
    while i < len(lines):
        line = lines[i]
        # fenced code block (``` ... ```) — escaped verbatim, never inline-parsed
        fence = re.match(r"^\s*```(\w*)\s*$", line)
        if fence:
            i += 1; code = []
            while i < len(lines) and not re.match(r"^\s*```\s*$", lines[i]):
                code.append(lines[i]); i += 1
            i += 1  # skip closing fence
            lang = fence.group(1)
            # mermaid fences render as diagrams: mermaid.js targets <pre class="mermaid">
            # and reads textContent (browser un-escapes entities), so escaping stays safe.
            if lang == "mermaid":
                out.append('<pre class="mermaid">' + html.escape("\n".join(code)) + "</pre>"); continue
            cls = f' class="lang-{lang}"' if lang else ""
            out.append(f"<pre><code{cls}>" + html.escape("\n".join(code)) + "</code></pre>"); continue
        # shortcode block (:::name ... :::). Attrs may be given as {key="val"}
        # OR as bare trailing text, which is treated as the title (agents often
        # write `:::callout Some title`).
        m = re.match(r"^:::(\w+)(?:\{([^}]*)\}|\s+(.+?))?\s*$", line)
        if m:
            attrs = _parse_attrs(m.group(2)) if m.group(2) else ({"title": m.group(3).strip()} if m.group(3) else {})
            name, body = m.group(1), []
            i += 1
            while i < len(lines) and not re.match(r"^:::\s*$", lines[i]):
                body.append(lines[i]); i += 1
            out.append(render_shortcode(name, body, attrs)); i += 1; continue
        # heading
        h = re.match(r"^(#{1,3})\s+(.*)", line)
        if h:
            lvl = len(h.group(1)); raw = h.group(2).strip()
            slug = _slugify(raw)
            if slug in seen_slugs:
                seen_slugs[slug] += 1; slug = f"{slug}-{seen_slugs[slug]}"
            else:
                seen_slugs[slug] = 0
            out.append(f'<h{lvl} id="{slug}">{inline(raw)}</h{lvl}>'); i += 1; continue
        # GFM table (header row + |---| separator on the next line)
        if "|" in line and i + 1 < len(lines) and _is_table_sep(lines[i + 1]):
            headers = _table_row(line); i += 2; rows = []
            while i < len(lines) and lines[i].strip() and "|" in lines[i]:
                rows.append(_table_row(lines[i])); i += 1
            thead = "".join(f"<th>{inline(c)}</th>" for c in headers)
            tbody = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows)
            out.append(f"<table><thead><tr>{thead}</tr></thead><tbody>{tbody}</tbody></table>"); continue
        # blockquote (one or more leading > lines)
        if line.lstrip().startswith(">"):
            quote = []
            while i < len(lines) and lines[i].lstrip().startswith(">"):
                quote.append(re.sub(r"^\s*>\s?", "", lines[i])); i += 1
            out.append("<blockquote>" + inline(" ".join(q.strip() for q in quote)) + "</blockquote>"); continue
        # list — ordered (1. 2.) or unordered (- *), flat, with continuation
        # lines folded into the current item. Without this a markdown list
        # collapses into a run-on paragraph (each item losing its own line).
        if re.match(r"^\s*([-*]|\d+\.)\s+\S", line):
            ordered = bool(re.match(r"^\s*\d+\.\s", line))
            items = []
            while i < len(lines):
                lm = re.match(r"^\s*([-*]|\d+\.)\s+(.*)", lines[i])
                if lm:
                    items.append(lm.group(2)); i += 1
                elif (lines[i].strip()
                      and not lines[i].lstrip().startswith(("#", ":::", "```", ">", "|"))):
                    if items: items[-1] += " " + lines[i].strip()  # wrapped item line
                    i += 1
                else:
                    break
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(it.strip())}</li>" for it in items) + f"</{tag}>")
            continue
        if line.strip() == "":
            i += 1; continue
        # paragraph — stop at any structural boundary so tables/code/quotes aren't absorbed
        para = [line]; i += 1
        while (i < len(lines) and lines[i].strip() != ""
               and not lines[i].startswith(":::") and not lines[i].startswith("#")
               and not lines[i].lstrip().startswith("```") and not lines[i].lstrip().startswith(">")
               and not re.match(r"^\s*([-*]|\d+\.)\s+\S", lines[i])
               and not ("|" in lines[i] and i + 1 < len(lines) and _is_table_sep(lines[i + 1]))):
            para.append(lines[i]); i += 1
        cls = ' class="lead"' if not any("<p" in o or "<h2" in o for o in out) else ""
        out.append(_para_html(" ".join(p.strip() for p in para), cls))
    return "\n".join(out)


def read_frontmatter(text):
    fm = {}
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            for line in text[4:end].split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1); fm[k.strip()] = v.strip()
    return fm

def resolve_theme(cli, fm, root):
    if cli: return cli
    if fm.get("theme"): return fm["theme"]
    cfg = root / "vault/explainers/config.json"
    if cfg.exists():
        import json
        try: return json.loads(cfg.read_text()).get("default_theme", "clean-flat")
        except Exception: pass
    return "clean-flat"

def find_theme_css(root, theme):
    for base in ("vault/explainers/themes", "system/explainers/themes"):
        p = root / base / theme / "theme.css"
        if p.exists(): return p
    return None

def main(argv):
    src = pathlib.Path(argv[0]); cli_theme = None; out = None
    if "--theme" in argv: cli_theme = argv[argv.index("--theme") + 1]
    if "--out" in argv:   out = argv[argv.index("--out") + 1]
    root = pathlib.Path(__file__).resolve().parents[4]   # .../system/addons/brain-explain/lib -> repo root
    text = src.read_text(encoding="utf-8")
    fm = read_frontmatter(text)
    theme = resolve_theme(cli_theme, fm, root)
    norm = (root / "system/explainers/norm.css").read_text(encoding="utf-8")
    tcss = find_theme_css(root, theme)
    theme_css = tcss.read_text(encoding="utf-8") if tcss else ""
    body = parse_body(split_frontmatter(text))
    # Only ship the mermaid runtime when a diagram is actually present — no bloat otherwise.
    mermaid_js = ""
    if 'class="mermaid"' in body:
        mermaid_js = (
            # Dubbelklik-zoom: diagrammen zijn vaak te klein op de pagina; een dubbelklik
            # opent een fullscreen-lightbox met een geschaalde kopie van het SVG.
            # Sluiten: klik of Escape. CSS bewust hier (alleen geladen mét diagrammen).
            "<style>\n"
            "pre.mermaid { cursor: zoom-in; }\n"
            ".mermaid-lightbox { position: fixed; inset: 0; display: none; background: rgba(20, 16, 28, 0.93); z-index: 999; padding: 3vmin; cursor: zoom-out; }\n"
            ".mermaid-lightbox.open { display: block; }\n"
            ".mermaid-lightbox svg { width: 100%; height: 100%; background: #fff; border-radius: 8px; }\n"
            "</style>\n"
            '<script type="module">\n'
            "import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';\n"
            "const dark = (document.documentElement.dataset.theme || '').includes('dark');\n"
            "mermaid.initialize({ startOnLoad: true, theme: dark ? 'dark' : 'neutral', securityLevel: 'strict' });\n"
            "const lb = document.createElement('div');\n"
            "lb.className = 'mermaid-lightbox';\n"
            "lb.addEventListener('click', () => lb.classList.remove('open'));\n"
            "document.addEventListener('keydown', (e) => { if (e.key === 'Escape') lb.classList.remove('open'); });\n"
            "document.body.appendChild(lb);\n"
            "for (const pre of document.querySelectorAll('pre.mermaid')) pre.title = 'Dubbelklik om te vergroten';\n"
            "document.addEventListener('dblclick', (e) => {\n"
            "  const svg = e.target.closest('pre.mermaid')?.querySelector('svg');\n"
            "  if (!svg) return;\n"
            "  const kopie = svg.cloneNode(true);\n"
            "  kopie.removeAttribute('width'); kopie.removeAttribute('height');\n"
            "  kopie.style.maxWidth = 'none'; kopie.style.width = '100%'; kopie.style.height = '100%';\n"
            "  lb.replaceChildren(kopie);\n"
            "  lb.classList.add('open');\n"
            "});\n"
            "</script>\n"
        )
    # CSS-only light/dark toggle (round button, top-right). No JS: a checkbox
    # + :has() steers color-scheme, and every theme value uses light-dark().
    # Both icons are monochrome (stroke=currentColor); the inactive one fades to
    # transparent. See system/explainers/norm.css for the mechanism.
    toggle = (
        '<div class="ex-mode"><input type="checkbox" id="ex-mode">'
        '<label for="ex-mode" title="Licht / donker" aria-label="Wissel licht of donker">'
        '<svg class="ic sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
        '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 '
        '1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
        '<svg class="ic moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
        '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg></label></div>\n')
    page = (f'<!doctype html>\n<html lang="nl" data-theme="{html.escape(theme)}">\n<head>\n'
            f'<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f'<style>\n{norm}\n{theme_css}\n</style>\n</head>\n<body>\n{toggle}'
            f'<div class="wrap"><article class="explainer">\n{body}\n</article></div>\n{mermaid_js}</body>\n</html>\n')
    if out and out != "-": pathlib.Path(out).write_text(page, encoding="utf-8")
    else: sys.stdout.write(page)

if __name__ == "__main__":
    main(sys.argv[1:])
