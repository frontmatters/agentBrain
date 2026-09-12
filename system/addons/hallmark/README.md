---
date: 2026-07-26
type: system
tags: [addon, skills, design, hallmark, together-ai]
id: c15921dd-fb27-52df-8354-71f3266568d5
---

# Hallmark

Registry entry for the **Hallmark** design skill: an anti-AI-slop ruleset for
AI coding assistants (build / audit / redesign / study), made by Together AI.
Vendored into `vault/skills/hallmark/` (not just referenced) so the full
`references/` tree ships alongside `SKILL.md` and gets wired into every agent
by `scripts/setup/setup-skills.sh`.

- **Use**: default verb builds new UI from a brief; `hallmark audit <target>`
  scores existing code against 57 anti-pattern gates (no edits); `hallmark
  redesign <target>` keeps content/IA/brand but rebuilds the visual structure;
  `hallmark study <screenshot|URL>` extracts a design's DNA (macrostructure,
  type-pairing, colour anchor) and can emit a portable `design.md`.
- **Privacy**: local — pure markdown instructions, no network calls, no
  executable code (verified: no non-`.md` files, no `curl`/`fetch`/`exec`/
  `child_process`/`eval` patterns anywhere in the skill tree).
- **Relation to existing skills** (cross-referenced both ways via each
  skill's `related:` frontmatter, 2026-07-26):
  - `flux-design-system` — this vault's own token/component reference; use
    Hallmark for a greenfield brief not tied to these tokens.
  - `uxray` — the 12-axis, evidence-captured audit; Hallmark's own
    `audit <target>` verb is a lighter, no-setup punch-list alternative
    scored against its 57 slop-test gates (no screenshots, no score history).
  - `design-loop` — autonomous HTML/CSS variant iteration; Hallmark's
    20-theme catalog + custom-OKLCH branch can seed or stand in for the
    per-iteration variant it critiques.
  - `technique-transplant` — harvests a reference site's composition/motion
    grammar; Hallmark's `study <screenshot|URL>` verb does the adjacent job
    of DNA extraction (macrostructure, type-pairing, colour anchor) and can
    emit a portable `design.md`.
  - `brand-guidelines-maker` — builds a persistent, named brand kit; hand
    that kit to Hallmark's custom-theme branch as grounding context so
    repeated builds stay on-brand across sessions.

## Upstream & license

- **Upstream**: <https://github.com/nutlope/hallmark> — MIT licensed, made by
  Together AI. Website: <https://www.usehallmark.com>.
- **License**: MIT (see upstream `LICENSE`). Safe to vendor.

## Install per client

- **Claude Code / Cursor / Codex**: `npx skills add nutlope/hallmark` (per
  upstream README) installs into `~/.claude/skills/hallmark/`,
  `.cursor/rules/hallmark.mdc`, or `~/.codex/skills/hallmark/` respectively.
- **Pi (this vault)**: vendored copy at `vault/skills/hallmark/`, wired into
  `~/.pi/agent/skills/hallmark` (symlink) by `scripts/setup/setup-skills.sh` — no
  separate `npx` install needed.

## Update

Hallmark evolves upstream (fifty-seven slop-test gates, twenty themes as of
v1.1.0). To refresh the vendored copy:

```bash
rm -rf /tmp/hallmark-update && git clone --depth 1 https://github.com/nutlope/hallmark /tmp/hallmark-update
rsync -a --delete /tmp/hallmark-update/skills/hallmark/ ~/agentBrain/vault/skills/hallmark/
```

Re-run the security spot-check (no non-`.md` files, no exec/network patterns)
before trusting the refreshed copy, then bump `version:` in `manifest.md` to
match upstream `package.json`.

## Uninstall

```bash
rm -rf ~/agentBrain/vault/skills/hallmark
bash ~/agentBrain/scripts/setup/setup-skills.sh   # prunes the now-dangling agent symlinks
```

## Supply-chain notes

- Pure markdown skill: no scripts, no `postinstall`/`preinstall` hooks, no
  hardcoded credentials or IPs found in a manual scan (2026-07-26).
- MIT license, public GitHub repo, backed by Together AI — low provenance
  risk, but re-verify on each manual update above (upstream can add
  executable content in a future release; re-scan before trusting it).
