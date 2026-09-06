#!/usr/bin/env python3
"""port-skills-hermes.py — reshape agentBrain SKILL.md files into Hermes' shape.

Hermes (nousresearch/hermes-agent) reads skills with a different SKILL.md
convention than agentBrain: Overview / Prerequisites / Inputs / Workflow /
Tools Reference / Tips (see system/agent-config/hermes.md §3). A raw symlink of
an agentBrain SKILL.md therefore loads awkwardly. This porter keeps agentBrain
as the single source of truth and generates correctly-shaped copies into
Hermes' skills dir.

Design:
- Source of truth stays in system/skills/ + vault/skills/. Never edited here.
- Output goes to <HERMES_HOME>/skills/<name>/SKILL.md, each stamped with a
  marker so we only ever overwrite brain-ported skills and never touch a
  Hermes-native one.
- Lossless: the full original body is preserved under ## Workflow, so nothing
  the skill said is dropped — only re-framed with Hermes' section headers.
- Idempotent: re-running overwrites brain-ported skills in place; removes ones
  whose source disappeared.

Usage: port-skills-hermes.py [--hermes-home DIR] [--dry-run]
Env: HERMES_HOME (default ~/.hermes), AGENTBRAIN_HOME (default ~).
Exits 2 if Hermes home does not exist (not applicable — mirrors setup-hermes.sh).
"""
from __future__ import annotations
import os, re, sys, shutil
from pathlib import Path

MARKER = "x-agentbrain-ported"  # frontmatter stamp = brain-ported

def vault_root() -> Path:
    # scripts/ sits at the checkout root, sibling to system/ and local/.
    return Path(__file__).resolve().parent.parent

def parse_frontmatter(text: str):
    """Return (frontmatter_dict_ish, body). Only name/description are read."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm_raw = text[3:end].strip("\n")
    body = text[end + 4:].lstrip("\n")
    fm = {}
    key = None
    for line in fm_raw.splitlines():
        m = re.match(r"^(\w[\w-]*):\s*(.*)$", line)
        if m:
            key = m.group(1)
            fm[key] = m.group(2).strip()
        elif key and line.strip():  # folded/continued value (e.g. `description: >`)
            fm[key] = (fm[key] + " " + line.strip()).strip()
    return fm, body

def hermes_skill(name: str, description: str, body: str) -> str:
    desc = description.strip().strip(">|").strip() or f"The {name} skill."
    # Pull a Tips/Notes section out of the body if the skill has one, so Tips
    # isn't a hollow header; otherwise give a truthful generic tip.
    tips = ""
    m = re.search(r"^##+\s*(Notes|Tips)\b.*?$(.*?)(?=^##\s|\Z)", body,
                  re.M | re.S)
    if m:
        tips = m.group(2).strip()
    if not tips:
        tips = ("Prefer reusing agentBrain scripts and MCP tools over ad-hoc "
                "work; this skill's Workflow below is the authoritative procedure.")
    return f"""---
name: {name}
description: {desc}
{MARKER}: true
---

# {name}

## Overview

{desc}

## Prerequisites

- An agentBrain vault checkout is present and readable.
- The agentBrain MCP tools (`brain_search`, `brain_read`, …) are wired into
  Hermes (`hermes mcp add agentbrain …` — see `setup-hermes.sh`). Some steps in
  the Workflow call `brain_search`/`brain_read` or vault scripts.

## Inputs

Free-form arguments as described in the Workflow. Most agentBrain skills take an
optional topic/slug/path; pass what the Workflow asks for.

## Workflow

The following is the authoritative agentBrain procedure for this skill,
preserved verbatim. Follow it top to bottom.

{body.strip()}

## Tools Reference

- agentBrain MCP: `brain_search`, `brain_read`, `brain_recent`, plus any
  skill-specific tools named in the Workflow.
- Vault scripts under `scripts/` and addon binaries under `system/addons/*/bin/`
  referenced above.

## Tips

{tips}
"""

def discover(root: Path):
    for base in (root / "system" / "skills", root / "local" / "skills"):
        if not base.is_dir():
            continue
        for skill_md in sorted(base.glob("*/SKILL.md")):
            yield skill_md.parent.name, skill_md

def is_brain_ported(skill_md: Path) -> bool:
    # Look for the stamp inside the frontmatter block, not a fixed char window —
    # some skills have very long descriptions that push the marker line well
    # past any byte cap, which would falsely read them as Hermes-native.
    try:
        text = skill_md.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    fm, _ = parse_frontmatter(text)
    return MARKER in fm

def main() -> int:
    dry = "--dry-run" in sys.argv
    home = os.environ.get("HERMES_HOME") or str(
        Path(os.environ.get("AGENTBRAIN_HOME", str(Path.home()))) / ".hermes")
    if "--hermes-home" in sys.argv:
        home = sys.argv[sys.argv.index("--hermes-home") + 1]
    hermes = Path(home)
    if not hermes.is_dir():
        print(f"port-skills-hermes: {hermes} not found (Hermes not installed) — skip",
              file=sys.stderr)
        return 2

    root = vault_root()
    skills_dir = hermes / "skills"
    skills_dir.mkdir(parents=True, exist_ok=True)

    wanted = {}
    for name, skill_md in discover(root):
        wanted[name] = skill_md  # vault/ overrides system/ on name clash

    written, removed = 0, 0
    for name, skill_md in wanted.items():
        fm, body = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        out_dir = skills_dir / name
        out = out_dir / "SKILL.md"
        # Never clobber a Hermes-native skill that happens to share a name.
        if out.exists() and not is_brain_ported(out):
            print(f"  skip (Hermes-native, not overwritten): {name}")
            continue
        content = hermes_skill(name, fm.get("description", ""), body)
        if dry:
            print(f"  would write: {out}")
        else:
            out_dir.mkdir(parents=True, exist_ok=True)
            out.write_text(content, encoding="utf-8")
        written += 1

    # Prune brain-ported skills whose source disappeared.
    if skills_dir.is_dir():
        for d in sorted(skills_dir.iterdir()):
            sm = d / "SKILL.md"
            if d.is_dir() and d.name not in wanted and sm.exists() and is_brain_ported(sm):
                if dry:
                    print(f"  would remove (source gone): {d.name}")
                else:
                    shutil.rmtree(d)
                removed += 1

    verb = "would port" if dry else "ported"
    print(f"port-skills-hermes: {verb} {written} skill(s) -> {skills_dir}"
          + (f", pruned {removed}" if removed else ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())
