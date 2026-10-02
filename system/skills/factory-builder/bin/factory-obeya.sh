#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# factory-obeya.sh: one place that shows everything about a factory.
#
# An obeya ("big room") puts the whole state of a line on one wall. This builds
# it from four sources, each read fresh, so the page cannot go stale:
#
#   Stations         measured: the lanes in factory.json (version, sha,
#                    uncommitted work), or the JSON a factory's own board prints
#                    (obeya.stations)
#   Andon            kept by hand: what is stopped or waiting, one line per
#                    pulled cord, each with "since YYYY-MM-DD"
#   Next             the factory's open backlog items, by priority then rank
#   Recently done    the newest entries of the factory's log
#
# Only the andon and the backlog priorities are hand work, and each lives in its
# own place. Every path, heading, threshold and count comes from factory.json
# "obeya" over ../obeya.defaults.json; nothing is fixed here.
#
#   factory-obeya.sh [--factory PATH]            print the obeya (Markdown)
#   factory-obeya.sh [--factory PATH] --write    and write it to obeya.page
#   factory-obeya.sh [--factory PATH] --json     summary for doctor and registry
#   factory-obeya.sh [--factory PATH] --init     create the andon from the template
#
# FACTORY_OBEYA_TODAY=YYYY-MM-DD fixes "today" (tests). Exit 2 on a factory.json
# that cannot be read; a missing source is reported on the page, never fatal.
set -euo pipefail
SKILL="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
FACTORY="" MODE="print"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--factory) FACTORY="$2"; shift 2 ;;
		--write) MODE="write"; shift ;;
		--json) MODE="json"; shift ;;
		--init) MODE="init"; shift ;;
		-h|--help) sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "factory-obeya: unknown option: $1" >&2; exit 2 ;;
	esac
done
FACTORY="${FACTORY_PATH:-${FACTORY:-$PWD}}"
FACTORY="$(cd "$FACTORY" && pwd)"

exec python3 - "$FACTORY" "$SKILL" "$MODE" <<'PY'
import datetime, json, os, pathlib, re, subprocess, sys

factory, skill, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

def fail(msg):
    print(f"factory-obeya: {msg}", file=sys.stderr); sys.exit(2)

try:
    data = json.loads((factory / "factory.json").read_text())
except FileNotFoundError:
    fail(f"no factory.json in {factory}")
except ValueError as e:
    fail(f"factory.json is not valid JSON: {e}")
defaults = json.loads((skill / "obeya.defaults.json").read_text())
cfg = {k: v for k, v in defaults.items() if not k.startswith("//")}
own = data.get("obeya") or {}
if not isinstance(own, dict):
    fail('factory.json "obeya" must be an object')
cfg.update({k: v for k, v in own.items() if not k.startswith("//")})
cfg["sections"] = {**defaults["sections"], **(own.get("sections") or {})}
project = data.get("project") or cfg.get("project") or factory.name

def resolve(raw):
    if not raw:
        return None
    p = pathlib.Path(os.path.expanduser(str(raw)))
    return p if p.is_absolute() else factory / p

today = datetime.date.fromisoformat(os.environ["FACTORY_OBEYA_TODAY"]) if os.environ.get("FACTORY_OBEYA_TODAY") else datetime.date.today()
andon_path, page_path = resolve(cfg["andon"]), resolve(cfg["page"])

# ── init ────────────────────────────────────────────────────────────────────
if mode == "init":
    if andon_path.exists():
        print(f"factory-obeya: andon exists, left as is: {andon_path}"); sys.exit(0)
    andon_path.parent.mkdir(parents=True, exist_ok=True)
    text = (skill / "templates" / "andon.md").read_text()
    text = text.replace("{project}", project).replace("{working}", cfg["sections"]["working"]).replace("{stopped}", cfg["sections"]["stopped"])
    andon_path.write_text(text)
    print(f"factory-obeya: created {andon_path}"); sys.exit(0)

# ── stations ────────────────────────────────────────────────────────────────
def git(path, *args):
    try:
        return subprocess.run(["git", "-C", str(path), *args], capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""

def lane_version(path):
    v = path / "VERSION"
    if v.is_file():
        return v.read_text().strip() or "?"
    pj = path / "package.json"
    if pj.is_file():
        try:
            return json.loads(pj.read_text()).get("version") or "?"
        except ValueError:
            return "?"
    return "?"

def stations():
    """(rows, note): rows of (station, fact, value)."""
    cmd = cfg.get("stations")
    if cmd:
        try:
            r = subprocess.run(cmd, shell=True, cwd=factory, capture_output=True, text=True, timeout=180)
            doc = json.loads(r.stdout) if r.returncode == 0 else None
        except (subprocess.TimeoutExpired, ValueError):
            doc = None
        if not isinstance(doc, dict):
            return [], f"not measured: `{cmd}` gave no JSON object"
        rows = []
        for top, val in doc.items():
            if isinstance(val, dict):
                for k, v in val.items():
                    if isinstance(v, dict):
                        rows.append((f"{top}.{k}", "", ", ".join(f"{a} {b}" for a, b in v.items())))
                    else:
                        rows.append((top, k, str(v)))
            else:
                rows.append((top, "", str(val)))
        return rows, f"from `{cmd}`"
    # The lanes as the doctor and the registry see them: one normalizer for
    # every profile (standard "lanes", composite "framework"), so the three
    # tools cannot disagree about where a lane is.
    sys.path.insert(0, str(skill / "bin"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("factory_profile", skill / "bin" / "factory-profile.py")
    prof = importlib.util.module_from_spec(spec); spec.loader.exec_module(prof)
    try:
        norm = prof.normalize(factory)
    except (OSError, ValueError, TypeError, KeyError) as e:
        return [], f"not measured: {e}"
    lanes = norm["lanes"]
    if not any(lanes.values()):
        return [], f'not measured: the {norm["profile"]} profile declares no lanes and "obeya.stations" is not set'
    rows = []
    for name, raw in lanes.items():
        p = pathlib.Path(raw) if raw else None
        if not p or not p.is_dir():
            rows.append((name, "missing", str(p) if p else "not declared")); continue
        sha = git(p, "rev-parse", "--short", "HEAD") or "not a git worktree"
        dirty = len([l for l in git(p, "status", "--porcelain").splitlines() if l])
        rows.append((name, lane_version(p), f"{sha}" + (f", {dirty} uncommitted" if dirty else "")))
    return rows, f'from the lanes of the {norm["profile"]} profile'


# ── andon ───────────────────────────────────────────────────────────────────
since_re = re.compile(cfg["since"], re.I)

def andon():
    """{working: [...], stopped: [(text, days|None)]}, or None when the file is absent."""
    if not andon_path or not andon_path.is_file():
        return None
    text = andon_path.read_text(errors="replace")
    body = text
    if text.startswith("---"):
        end = text.find("\n---", 3)
        body = text[end + 4:] if end > 0 else text
    out, current = {"working": [], "stopped": []}, None
    want = {v.strip().lower(): k for k, v in cfg["sections"].items()}
    for line in body.splitlines():
        h = re.match(r"^#{2,}\s+(.*?)\s*$", line)
        if h:
            current = want.get(h.group(1).lower()); continue
        item = re.match(r"^\s*[-*]\s+(.*\S)\s*$", line)
        if current and item:
            txt = item.group(1)
            days = None
            m = since_re.search(txt)
            if m:
                try:
                    days = (today - datetime.date.fromisoformat(m.group(1))).days
                except ValueError:
                    days = None
            out[current].append((txt, days) if current == "stopped" else txt)
    return out

# ── next ────────────────────────────────────────────────────────────────────
def frontmatter(text):
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    fm = {}
    for line in text[3:end if end > 0 else 0].splitlines():
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*?)\s*$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return fm

def backlog():
    """(items, note)."""
    d = resolve(cfg.get("backlog"))
    if not d:
        return [], "not configured (obeya.backlog)"
    if not d.is_dir():
        return [], f"missing: {d}"
    prios = [p.lower() for p in cfg["priorities"]]
    open_st = {s.lower() for s in cfg["openStatuses"]}
    want_project = cfg.get("project") or data.get("project")
    items = []
    for f in sorted(d.glob("*.md")):
        text = f.read_text(errors="replace")
        fm = frontmatter(text)
        if want_project and fm.get("project") != want_project:
            continue
        if fm.get("status", "").lower() not in open_st:
            continue
        title = next((l[2:].strip() for l in text.splitlines() if l.startswith("# ")), f.stem)
        pr = fm.get("priority", "").lower()
        try:
            rank = float(fm.get("rank", ""))
        except ValueError:
            rank = float("inf")
        items.append(((prios.index(pr) if pr in prios else len(prios)), rank, f.name, title, pr or "none", f))
    items.sort(key=lambda x: (x[0], x[1], x[2]))
    return items[: int(cfg["next"])], f"{len(items)} open"

# ── recently done ───────────────────────────────────────────────────────────
def done():
    p = resolve(cfg.get("log"))
    if not p:
        return [], "not configured (obeya.log)"
    if not p.is_file():
        return [], f"missing: {p}"
    lines, inside = [], False
    for line in p.read_text(errors="replace").splitlines():
        h = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if h:
            if inside:
                break
            inside = h.group(2).strip().lower() == str(cfg["logSection"]).lower(); continue
        if not inside:
            continue
        m = re.match(r"^[-*]\s+(.*\S)", line)
        if m:
            lines.append(m.group(1))
        elif lines and re.match(r"^\s+\S", line):
            # an entry wrapped over several lines continues with an indent
            lines[-1] += " " + line.strip()
    if not lines and not inside:
        return [], f'no "{cfg["logSection"]}" section in {p.name}'
    return lines[: int(cfg["done"])], ""

# ── assemble ────────────────────────────────────────────────────────────────
st_rows, st_note = stations()
an = andon()
nx, nx_note = backlog()
dn, dn_note = done()
stale = int(cfg["staleDays"])

def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")

def link(path):
    vault = resolve(cfg.get("vault"))
    if vault and str(path).startswith(str(vault) + os.sep):
        return f"[[{os.path.relpath(path, vault)[:-3]}]]"
    return f"`{path}`"

if mode == "json":
    stopped = an["stopped"] if an else []
    ages = [d for _, d in stopped if d is not None]
    print(json.dumps({
        "project": project,
        "andon": None if an is None else {
            "path": str(andon_path), "working": len(an["working"]), "stopped": len(stopped),
            "oldestDays": max(ages) if ages else None,
            "stale": sum(1 for d in ages if d > stale), "undated": sum(1 for _, d in stopped if d is None)},
        "next": nx[0][3] if nx else None,
        "stations": st_note,
    }, indent=2))
    sys.exit(0)

out = [f"# {project} obeya", "",
       f"> Generated by `factory-obeya.sh` on {today.isoformat()}. Do not edit this page: change the andon, the backlog or the log. Andon: {link(andon_path) if andon_path else 'not configured'}.", ""]
out += ["## Stations", "", f"_{st_note}_", ""]
if st_rows:
    out += ["| Station | Fact | Value |", "|---|---|---|"] + [f"| {cell(a)} | {cell(b)} | {cell(c)} |" for a, b, c in st_rows]
out += ["", "## Andon", ""]
if an is None:
    out += [f"No andon at `{andon_path}`. Create it: `factory-obeya.sh --init`."]
else:
    out += [f"**{cfg['sections']['working']}**", ""] + ([f"- {w}" for w in an["working"]] or ["- (none)"])
    out += ["", f"**{cfg['sections']['stopped']}**", ""]
    if not an["stopped"]:
        out += ["- (none)"]
    for txt, days in an["stopped"]:
        age = "no date" if days is None else f"{days} day{'s' if days != 1 else ''}"
        flag = " **STALE**" if days is not None and days > stale else (" **UNDATED**" if days is None else "")
        out += [f"- {txt} ({age}){flag}"]
out += ["", "## Next", "", f"_{nx_note}_", ""]
out += [f"{i}. [{pr}] {cell(title)} ({link(f)})" for i, (_, _, _, title, pr, f) in enumerate(nx, 1)] or ["(none)"]
out += ["", "## Recently done", ""]
out += ([f"- {l}" for l in dn] or [f"({dn_note or 'none'})"])
page = "\n".join(out).rstrip() + "\n"

if mode == "print":
    print(page, end=""); sys.exit(0)

# write: a vault page carries the vault's frontmatter with the id its tool
# computes; any other page is plain Markdown. Rewritten only when the content
# (not the date line) changed, so an unchanged factory makes no noise.
vault, note_id = resolve(cfg.get("vault")), resolve(cfg.get("noteId"))
header = ""
if vault and note_id and str(page_path).startswith(str(vault) + os.sep):
    # The id tool seeds on the note's path relative to the brain root, the
    # directory that holds the vault, without the extension.
    rel = os.path.relpath(page_path, vault.parent)[:-3]
    ident = subprocess.run(["bash", str(note_id), rel], capture_output=True, text=True).stdout.strip()
    if not ident:
        fail(f"{note_id} gave no id for {rel}")
    header = f"---\ndate: {today.isoformat()}\ntype: reference\ntags: [obeya, generated, {project}]\nid: {ident}\n---\n\n"
new = header + page
# Only the dates are ignored: the generated line also names the andon path,
# and a moved factory must rewrite it.
strip = lambda s: re.sub(r"(?m)^date: .*$", "", re.sub(r"(> Generated by `factory-obeya.sh` on )\d{4}-\d{2}-\d{2}", r"\1", s))
if page_path.exists() and strip(page_path.read_text()) == strip(new):
    print(f"factory-obeya: unchanged: {page_path}"); sys.exit(0)
page_path.parent.mkdir(parents=True, exist_ok=True)
tmp = page_path.with_suffix(".md.tmp")
tmp.write_text(new); tmp.replace(page_path)
print(f"factory-obeya: wrote {page_path}")
PY
