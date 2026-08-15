#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# onboard-wizard.sh — model-free onboarding: walk the canonical fixed-choice
# intake (system/skills/onboard/choices.json) as terminal menus and write the
# personal preference files. Completes the core of /onboard without any AI
# provider — the /onboard skill later refines (addons, org/team, spaces, your
# devices & services) via its skip-if-done contract.
#
# Flow (profile short path, 5 interactions):
#   profile → review screen (detection + profile, checkboxes) → language
#   (default from OS locale) → autonomy → updates (real channel names).
#   "no profile" walks the full question flow. Source hierarchy per review
#   row: detected > profile suggestion > "(fill in later)".
#
# Modes:
#   interactive (default) — asks; needs a TTY.
#   AB_WIZARD_DEFAULTS=1  — take every default silently (tests / --defaults express).
#   AB_WIZARD_PLAIN=1     — force plain numbered input (no raw-key checkboxes).
set -euo pipefail
VAULT="${VAULT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Interactive needs a controlling terminal — stdin-as-tty OR a readable
# /dev/tty (the curl | bash case: stdin is the pipe, the terminal still exists).
if [ "${AB_WIZARD_DEFAULTS:-}" != "1" ] && [ ! -t 0 ] && ! ( : < /dev/tty ) 2>/dev/null; then
	echo "onboard-wizard: no TTY — run interactively or set AB_WIZARD_DEFAULTS=1" >&2
	exit 2
fi
python3 - "$VAULT" <<'PY'
import json, os, re, subprocess, sys
VAULT = sys.argv[1]
DEFAULTS = os.environ.get("AB_WIZARD_DEFAULTS") == "1"
# AB_CHOICES_JSON: test/override path — lets a fixed wizard run against a vault
# whose shipped choices.json is older (e.g. a checkout pinned to a release tag).
C = json.load(open(os.environ.get("AB_CHOICES_JSON") or f"{VAULT}/system/skills/onboard/choices.json"))
PREFS = f"{VAULT}/local/preferences/personal"
DIM, GRN, CYA, RST = "\033[2m", "\033[32m", "\033[36m", "\033[0m"

# The program itself arrives on stdin (heredoc), so input() would hit EOF
# immediately — even on a real terminal. Interactive answers MUST come from
# the controlling terminal instead.
TTY = None
if not DEFAULTS:
    try:
        TTY = open("/dev/tty")
    except OSError:
        print("onboard-wizard: no controlling terminal — taking every default.", file=sys.stderr)
        DEFAULTS = True

def read_answer(prompt):
    print(prompt, end="", flush=True)
    line = TTY.readline()
    if line == "":  # ctrl-D: accept the default, don't crash
        print()
        return ""
    return line.strip()

def _print_options(opts, default_idx):
    for i, o in enumerate(opts):
        tag = "(default) " if i == default_idx else ""
        d = f'{DIM}{tag}{o.get("desc", "")}{RST}'
        print(f"   {i+1}) {o['value']:<22} {d}")

def _default_idx(opts, detected):
    # A detected value (OS, editor, locale) becomes the default when it matches.
    if detected:
        for i, o in enumerate(opts):
            if o["value"].lower() == detected.lower():
                return i
    return 0

def ask_choice(name, field, question, detected=None):
    opts = field["options"]
    di = _default_idx(opts, detected)
    print(f"\n{CYA}? {question}{RST}")
    _print_options(opts, di)
    if DEFAULTS:
        pick = di
    else:
        raw = read_answer(f"   choice [{di+1}]: ")
        pick = int(raw) - 1 if raw.isdigit() and 1 <= int(raw) <= len(opts) else di
    if opts[pick].get("custom") and not DEFAULTS:
        own = read_answer("   your own: ")
        if own:
            print(f"   {GRN}→ {own}{RST}")
            return own
        pick = di
    print(f"   {GRN}→ {opts[pick]['value']}{RST}")
    return opts[pick]["value"]

def _checkbox_capable():
    return (TTY is not None and os.environ.get("AB_WIZARD_PLAIN") != "1"
            and os.environ.get("TERM", "") != "dumb")

def _multi_checkbox(opts, di, question):
    # Checkbox picker on the raw terminal: arrows move, space (or 1-9) toggles,
    # enter confirms. Rows may carry a pre-set "on" state (review screen);
    # otherwise only the default row starts checked. Raises on anything
    # unusual — the caller falls back to plain input, so this can never
    # strand the wizard.
    import shutil, termios, tty as _tty
    fd = TTY.fileno()
    n = len(opts)
    preset = any("on" in o for o in opts)
    checked = [bool(o["on"]) if "on" in o else (i == di) for i, o in enumerate(opts)]
    cur = di
    width = shutil.get_terminal_size((80, 24)).columns
    print(f"\n{CYA}? {question}{RST}  {DIM}(space = toggle · enter = confirm · arrows = move){RST}")
    def render(first=False):
        if not first:
            sys.stdout.write(f"\x1b[{n}A")
        for i, o in enumerate(opts):
            arrow = "▸" if i == cur else " "
            box = "[x]" if checked[i] else "[ ]"
            line = f" {arrow} {box} {o['value']:<22} {o.get('desc', '')}"
            line = line[: max(width - 1, 20)]
            pre, _, desc = line.partition(o["value"])
            sys.stdout.write(f"\x1b[2K{pre}{o['value']}{DIM}{desc}{RST}\n")
        sys.stdout.flush()
    old = termios.tcgetattr(fd)
    try:
        _tty.setcbreak(fd)
        render(True)
        while True:
            ch = TTY.read(1)
            if ch in ("\r", "\n"):
                break
            if ch == " ":
                checked[cur] = not checked[cur]
            elif ch == "\x1b" and TTY.read(1) == "[":
                k = TTY.read(1)
                if k == "A":
                    cur = (cur - 1) % n
                elif k == "B":
                    cur = (cur + 1) % n
            elif ch.isdigit() and 1 <= int(ch) <= min(n, 9):
                cur = int(ch) - 1
                checked[cur] = not checked[cur]
            render()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    picks = [o["value"] for i, o in enumerate(opts) if checked[i] and not o.get("custom")]
    if any(checked[i] and o.get("custom") for i, o in enumerate(opts)):
        own = read_answer("   your own (comma-separate multiple): ")
        picks += [p.strip() for p in own.split(",") if p.strip()]
    if not picks and not preset:
        picks = [opts[di]["value"]]
    return picks

def ask_multi(name, field, question, detected=None):
    # Numbers comma-separated; anything non-numeric is taken verbatim as your
    # own answer — there is always a way to type something not in the list.
    opts = field["options"]
    di = _default_idx(opts, detected)
    if not DEFAULTS and _checkbox_capable():
        try:
            picks = _multi_checkbox(opts, di, question)
            val = ", ".join(dict.fromkeys(picks))
            print(f"   {GRN}→ {val}{RST}")
            return val
        except Exception:
            pass  # plain path below
    print(f"\n{CYA}? {question}{RST}")
    _print_options(opts, di)
    if DEFAULTS:
        picks = [opts[di]["value"]]
    else:
        raw = read_answer(f"   numbers, comma-separated — or type your own [{di+1}]: ")
        picks, custom_asked = [], False
        for part in (p.strip() for p in raw.split(",") if p.strip()):
            if part.isdigit() and 1 <= int(part) <= len(opts):
                o = opts[int(part) - 1]
                if o.get("custom"):
                    custom_asked = True
                else:
                    picks.append(o["value"])
            else:
                picks.append(part)
        if custom_asked:
            own = read_answer("   your own (comma-separate multiple): ")
            picks += [p.strip() for p in own.split(",") if p.strip()]
        if not picks:
            picks = [opts[di]["value"]]
    val = ", ".join(dict.fromkeys(picks))
    print(f"   {GRN}→ {val}{RST}")
    return val

def ask_text(question, suggestion=""):
    print(f"\n{CYA}? {question}{RST}")
    if DEFAULTS:
        print(f"   {GRN}→ {suggestion or '(skipped)'}{RST}")
        return suggestion
    raw = read_answer(f"   [{suggestion}]: ")
    return raw or suggestion

# ── Detection (best-effort, bounded; a default provider, never a gate) ──
def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""

os_name = sh("uname -s").replace("Darwin", "macOS")

def detect_locale_language():
    loc = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
    if not loc:
        loc = sh("defaults read -g AppleLocale 2>/dev/null")
    pref = loc.split("_")[0].split(".")[0].split("-")[0].lower()
    return {"en": "English", "nl": "Nederlands", "de": "Deutsch", "fr": "Français",
            "es": "Español", "zh": "中文", "ja": "日本語"}.get(pref)

def detect_editor():
    import shutil
    for cmd, val in (("cursor", "Cursor"), ("code", "VS Code"), ("zed", "Zed"),
                     ("nvim", "Neovim / Vim")):
        if shutil.which(cmd):
            return val
    for app, val in (("Cursor.app", "Cursor"), ("Visual Studio Code.app", "VS Code"),
                     ("Zed.app", "Zed")):
        if os.path.exists(f"/Applications/{app}"):
            return val
    e = os.environ.get("EDITOR", "")
    if "vim" in e:
        return "Neovim / Vim"
    if "code" in e:
        return "VS Code"
    return None

def scan_developer():
    # Cheap evidence scan of ~/Developer (top-level projects only): which
    # languages/hosts does this person demonstrably use? Bounded and silent.
    langs, hosts = [], []
    dev = os.path.expanduser("~/Developer")
    if not os.path.isdir(dev):
        return langs, hosts
    try:
        for e in sorted(os.listdir(dev))[:60]:
            d = os.path.join(dev, e)
            if not os.path.isdir(d):
                continue
            for marker, lang in (("tsconfig.json", "TypeScript"), ("Cargo.toml", "Rust"),
                                 ("go.mod", "Go"), ("pyproject.toml", "Python"),
                                 ("requirements.txt", "Python"), ("package.json", "JavaScript")):
                if lang not in langs and os.path.exists(os.path.join(d, marker)):
                    langs.append(lang)
            cfg = os.path.join(d, ".git", "config")
            if os.path.exists(cfg):
                txt = open(cfg, errors="ignore").read()
                for pat, host in (("github.com", "GitHub"), ("gitlab", "GitLab"),
                                  ("gitea", "Gitea"), ("bitbucket", "Bitbucket"),
                                  ("codeberg", "Codeberg")):
                    if host not in hosts and pat in txt:
                        hosts.append(host)
    except Exception:
        pass
    return langs, hosts

QUESTIONS = {
    "language":   "What language do you prefer for conversation?",
    "artifactLanguage": "Keep code, commits & docs in English?",
    "verbosity":  "How verbose should the agent be?",
    "askFirst":   "Ask before acting, or just do trivial things?",
    "autonomy":   "How autonomous may the agent be?",
    "design":     "Dark mode, light mode, or both?",
    "decision":   "How do you approach technical decisions?",
    "channel":    "How eagerly do you want agentBrain updates?",
    "updateMode": "How should updates be applied?",
}
answers = {}
fields = C["fields"]

def full_flow():
    # The complete question walk — DEFAULTS mode, "no profile", and older
    # choices.json (no profiles section) all land here.
    order = ["language", "artifactLanguage", "verbosity", "askFirst", "autonomy",
             "design", "decision", "channel", "updateMode"]
    for name in order:
        f = fields.get(name)
        if not f or f.get("type") != "choice":
            continue
        cond = f.get("condition")
        # condition {"field": X, "not": V} = ask only when answers[X] != V.
        if cond and answers.get(cond.get("field")) == cond.get("not"):
            continue
        answers[name] = ask_choice(name, f, QUESTIONS[name])

    def ask_field(key, question, detected=None):
        # Enum-first (fixed choices with a custom escape); text only as the
        # backward-compat path for an older choices.json.
        f = fields.get(key, {})
        if f.get("type") == "choice":
            return ask_choice(key, f, question, detected)
        if f.get("type") == "multi":
            return ask_multi(key, f, question, detected)
        return ask_text(f"{question}", detected or "")

    answers["os"] = ask_field("os", "Primary OS? (detected)", os_name)
    answers["editor"] = ask_field("editor", "Editor? (detected)", detect_editor() or "VS Code")
    answers["languages"] = ask_field("languages", "Languages & frameworks you use most?")
    answers["hosting"] = ask_field("hosting", "Where do you host code?")

def short_path(profile):
    # Profile short path: one review screen instead of four tech questions,
    # then the three questions that actually change agent behaviour.
    pre = profile.get("preselect", {})
    scan_l, scan_h = scan_developer()
    known_l = [o["value"] for o in fields.get("languages", {}).get("options", [])]
    known_h = [o["value"] for o in fields.get("hosting", {}).get("options", [])]
    langs = list(dict.fromkeys(list(pre.get("languages", [])) + [l for l in scan_l if l in known_l]))
    hosts = list(dict.fromkeys(list(pre.get("hosting", [])) + [h for h in scan_h if h in known_h]))
    det_ed = detect_editor() or (pre.get("editor") or [None])[0]
    osn = (pre.get("os") or [None])[0] or os_name

    rows = [{"value": f"OS: {osn}", "desc": "detected", "on": True, "k": ("os", osn)}]
    if det_ed:
        rows.append({"value": f"editor: {det_ed}", "desc": "detected", "on": True, "k": ("editor", det_ed)})
    else:
        rows.append({"value": "editor: none yet", "desc": "nothing found — /onboard fills this later",
                     "on": False, "k": ("editor", None)})
    for l in langs:
        src = "profile + scan" if l in scan_l else "profile"
        rows.append({"value": l, "desc": src, "on": True, "k": ("lang", l)})
    for h in hosts:
        src = "your git remotes" if h in scan_h else "profile"
        rows.append({"value": h, "desc": src, "on": True, "k": ("host", h)})
    # The escape hatch must be VISIBLE in the list (a fresh machine has no scan
    # hits, so the profile view is easily incomplete — Gitea, Azure DevOps, …).
    # The checkbox picker's custom handling prompts for typed additions.
    rows.append({"value": "add your own", "desc": "e.g. Gitea, Azure DevOps, Vue",
                 "on": False, "custom": True, "k": ("custom", None)})

    q = "Does this look right? (toggle what's wrong)"
    picks = None
    if _checkbox_capable():
        try:
            picks = _multi_checkbox(rows, 0, q)
        except Exception:
            picks = None
    if picks is None:
        print(f"\n{CYA}? {q}{RST}")
        for i, r in enumerate(rows[:-1]):
            box = "[x]" if r["on"] else "[ ]"
            print(f"   {i+1}) {box} {r['value']:<26} {DIM}{r['desc']}{RST}")
        raw = read_answer("   numbers to toggle, comma-separated [enter = ok]: ")
        for part in (p.strip() for p in raw.split(",") if p.strip()):
            if part.isdigit() and 1 <= int(part) < len(rows):
                rows[int(part) - 1]["on"] = not rows[int(part) - 1]["on"]
        picks = [r["value"] for r in rows if r["on"]]
        extra = read_answer("   add anything? (comma-separated, e.g. Gitea, Vue) [enter = no]: ")
        picks += [p.strip() for p in extra.split(",") if p.strip()]

    sel = {"os": None, "editor": None, "lang": [], "host": []}
    row_values = {r["value"] for r in rows}
    for r in rows:
        kind, val = r["k"]
        if r["value"] in picks and val is not None:
            if kind in ("os", "editor"):
                sel[kind] = val
            else:
                sel[kind].append(val)
    # Typed additions (via the "add your own" row or the plain add-prompt):
    # canonicalize against the known option lists — hosts route to hosting,
    # everything else lands in languages verbatim.
    for item in (p for p in picks if p not in row_values):
        canon_h = next((v for v in known_h if v.lower() == item.lower()), None)
        if canon_h:
            sel["host"].append(canon_h)
        else:
            sel["lang"].append(next((v for v in known_l if v.lower() == item.lower()), item))

    answers["os"] = sel["os"] or os_name
    answers["editor"] = sel["editor"] or ""
    answers["languages"] = ", ".join(dict.fromkeys(sel["lang"]))
    answers["hosting"] = ", ".join(dict.fromkeys(sel["host"]))
    print(f"   {GRN}→ {answers['languages'] or '(fill in later)'} · {answers['hosting'] or '(fill in later)'}{RST}")

    # The three questions that earn their place.
    answers["language"] = ask_choice("language", fields["language"], QUESTIONS["language"],
                                     detected=detect_locale_language())
    cond = fields.get("artifactLanguage", {}).get("condition", {})
    if answers["language"] != cond.get("not", "English"):
        answers["artifactLanguage"] = ask_choice("artifactLanguage", fields["artifactLanguage"],
                                                 QUESTIONS["artifactLanguage"])

    answers["autonomy"] = ask_choice("autonomy", fields["autonomy"], QUESTIONS["autonomy"])
    # askFirst measures the same axis — derive it, but keep writing the line.
    answers["askFirst"] = ("ask before acting" if answers["autonomy"] == "ask often"
                           else "just do trivial things")

    # Updates: real channel names; apply-mode rides along, custom unlocks both.
    ch = fields["channel"]["options"]
    merged = [dict(o, desc=f'{o.get("desc", "")} · applies: {o.get("apply", "ask")}') for o in ch]
    merged.append({"value": "custom", "desc": "choose channel and apply-mode separately"})
    pick = ask_choice("updates", {"options": merged}, QUESTIONS["channel"])
    if pick == "custom":
        answers["channel"] = ask_choice("channel", fields["channel"], "Release channel?")
        answers["updateMode"] = ask_choice("updateMode", fields["updateMode"], QUESTIONS["updateMode"])
    else:
        answers["channel"] = pick
        answers["updateMode"] = next(o.get("apply", "ask") for o in ch if o["value"] == pick)

    # Deferred to /onboard: write the field default, marked as such.
    for key in ("verbosity", "design", "decision"):
        answers[key] = f'{fields[key]["options"][0]["value"]} (default — refine via /onboard)'

# ── Flow selection ──────────────────────────────────────────
PROFILES = C.get("profiles", {}).get("options", [])
profile = None
if not DEFAULTS:
    # Why this exists, honestly: the few answers below demonstrably change how
    # agents behave; everything deeper the brain learns while you work.
    print(f"\n{DIM}Your agents share one brain. Give it a few basics — your language, how")
    print("much autonomy you allow, how agentBrain may update itself — and every session")
    print("starts ahead instead of from zero. About two minutes. Everything stays")
    print(f"editable, and the deeper knowledge your brain picks up while you work.{RST}")
if not DEFAULTS and PROFILES:
    pv = ask_choice("profile", {"options": PROFILES},
                    C["profiles"].get("question", "What describes you best?"))
    profile = next((o for o in PROFILES if o["value"] == pv), None)

if profile and not profile.get("full"):
    short_path(profile)
else:
    full_flow()

answers.setdefault("artifactLanguage", "english-artifacts")
git_name, git_email = sh("git config user.name"), sh("git config user.email")

# derived locale (never asked — G6)
sup = C.get("locales", {}).get("supported", ["en", "nl"])
loc = {"English": "en", "Nederlands": "nl"}.get(answers.get("language", "English"), "en")
answers["_locale"] = loc

def write_pref(fname, title, body_lines):
    path = f"{PREFS}/{fname}"
    fm = ""
    if os.path.exists(path):
        txt = open(path).read()
        m = re.match(r"(?s)^(---\n.*?\n---\n)", txt)
        fm = m.group(1) if m else ""
    body = f"# {title}\n\n" + "\n".join(body_lines) + "\n"
    open(path, "w").write(fm + "\n" + body if fm else body)
    print(f"  {GRN}✓{RST} {fname}")

print(f"\n{DIM}Writing preferences…{RST}")
art = answers.get("artifactLanguage", "english-artifacts")
write_pref("communication.md", "Communication", [
    f"- Conversation language: {answers['language']} (UI locale: {loc})",
    f"- Artifacts (code, commits, docs): "
    + ("English" if art == "english-artifacts" else answers["language"]),
    f"- Verbosity: {answers['verbosity']}",
    f"- Acting: {answers['askFirst']}",
])
write_pref("tech-stack.md", "Tech Stack", [
    f"- Primary OS: {answers['os']}",
    f"- Editor: {answers['editor'] or '(fill in later)'}",
    f"- Languages & frameworks: {answers['languages'] or '(fill in later)'}",
    f"- Code hosting: {answers['hosting'] or '(fill in later)'}",
])
write_pref("workflow.md", "Workflow", [
    f"- Autonomy: {answers['autonomy']}",
])
write_pref("design-philosophy.md", "Design Philosophy", [
    f"- Theme: {answers['design']}",
])
write_pref("decision-making.md", "Decision Making", [
    f"- Approach: {answers['decision']}",
])
write_pref("identity.md", "Identity", [
    f"- Name: {git_name or '(set via git config)'}",
    f"- Email: {git_email or '(set via git config)'}",
    f"- Git identity: {git_name} <{git_email}>" if git_name else "- Git identity: (pending)",
])

# channel + update mode via the canonical mechanisms
subprocess.run(["bash", f"{VAULT}/scripts/channel.sh", "set", answers["channel"]],
               capture_output=True)
import pathlib
cfg_p = pathlib.Path(f"{VAULT}/local/update/config.json")
cfg = json.loads(cfg_p.read_text()) if cfg_p.exists() else {}
cfg["auto_update"] = answers["updateMode"]
cfg_p.parent.mkdir(parents=True, exist_ok=True)
cfg_p.write_text(json.dumps(cfg, indent=2) + "\n")
print(f"  {GRN}✓{RST} channel={answers['channel']} · updates={answers['updateMode']} · locale={loc}")
print(f"\n{GRN}Core onboarding complete.{RST} {DIM}Deepen later inside your agent: /onboard (addons, org/team scopes, spaces, your devices & services).{RST}")
PY
