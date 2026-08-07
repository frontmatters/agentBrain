#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# onboard-wizard.sh — model-free onboarding: walk the canonical fixed-choice
# intake (system/skills/onboard/choices.json) as numbered terminal menus and
# write the personal preference files. Completes the core of /onboard without
# any AI provider — the /onboard skill later refines (addons, org/team, spaces)
# via its skip-if-done contract.
#
# Modes:
#   interactive (default) — asks; needs a TTY.
#   AB_WIZARD_DEFAULTS=1  — take every default silently (tests / --defaults express).
set -euo pipefail
VAULT="${VAULT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ "${AB_WIZARD_DEFAULTS:-}" != "1" ] && [ ! -t 0 ]; then
	echo "onboard-wizard: no TTY — run interactively or set AB_WIZARD_DEFAULTS=1" >&2
	exit 2
fi
python3 - "$VAULT" <<'PY'
import json, os, re, subprocess, sys
VAULT = sys.argv[1]
DEFAULTS = os.environ.get("AB_WIZARD_DEFAULTS") == "1"
C = json.load(open(f"{VAULT}/system/skills/onboard/choices.json"))
PREFS = f"{VAULT}/local/preferences/personal"
DIM, GRN, CYA, RST = "\033[2m", "\033[32m", "\033[36m", "\033[0m"

def ask_choice(name, field, question):
    opts = field["options"]
    print(f"\n{CYA}? {question}{RST}")
    for i, o in enumerate(opts):
        d = f'{DIM}({"default) " if i == 0 else ""}{o.get("desc", "")}{RST}'
        print(f"   {i+1}) {o['value']:<22} {d}")
    if DEFAULTS:
        pick = 0
    else:
        raw = input(f"   choice [1]: ").strip()
        pick = int(raw) - 1 if raw.isdigit() and 1 <= int(raw) <= len(opts) else 0
    print(f"   {GRN}→ {opts[pick]['value']}{RST}")
    return opts[pick]["value"]

def ask_text(question, suggestion=""):
    print(f"\n{CYA}? {question}{RST}")
    if DEFAULTS:
        print(f"   {GRN}→ {suggestion or '(skipped)'}{RST}")
        return suggestion
    raw = input(f"   [{suggestion}]: ").strip()
    return raw or suggestion

QUESTIONS = {
    "language":   "What language do you prefer for conversation?",
    "artifactLanguage": "Keep code, commits & docs in English?",
    "verbosity":  "How verbose should the agent be?",
    "askFirst":   "Ask before acting, or just do trivial things?",
    "autonomy":   "How autonomous may the agent be?",
    "design":     "Dark mode, light mode, or both?",
    "decision":   "How do you approach technical decisions?",
    "channel":    "Release channel?",
    "updateMode": "How should updates be applied?",
}
answers = {}
fields = C["fields"]
order = ["language", "artifactLanguage", "verbosity", "askFirst", "autonomy",
         "design", "decision", "channel", "updateMode"]
for name in order:
    f = fields.get(name)
    if not f or f.get("type") != "choice":
        continue
    cond = f.get("condition")
    if cond and answers.get(cond.get("field")) == cond.get("not"):
        continue
    if cond and "not" in cond and answers.get(cond["field"]) != cond["not"]:
        pass
    if cond and answers.get(cond["field"], "") == "English" and cond.get("not") == "English":
        continue
    answers[name] = ask_choice(name, f, QUESTIONS[name])

# a few honest text questions (detected where possible)
def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""
os_name = sh("uname -s").replace("Darwin", "macOS")
editor = os.environ.get("EDITOR", "") or "VS Code"
answers["os"] = ask_text("Primary OS? (detected)", os_name)
answers["editor"] = ask_text("Editor? (detected)", editor)
answers["languages"] = ask_text("Languages & frameworks you use most?", "")
answers["hosting"] = ask_text("Where do you host code?", "")
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
    f"- Editor: {answers['editor']}",
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
print(f"\n{GRN}Core onboarding complete.{RST} {DIM}Deepen later inside your agent: /onboard (addons, org/team scopes, spaces).{RST}")
PY
