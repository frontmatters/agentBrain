---
date: 2026-06-25
type: system
tags: [addon, brain-explain, explainers, themes, renderer]
id: dcd28c16-d870-5b05-950a-ca4040a24385
---

# brain-explain

Turns a markdown note (frontmatter + shortcodes + wikilinks) into a readable,
themed HTML page. Three layers: **content** (markdown source), **theme** (CSS skin,
free), **page** (generated HTML, sugar). Norms (OKLCH, readable body, no uxray
bans) are enforced by `scripts/checks/check-explainers.sh` for every theme.

## Use
- `brain-explain render <note.md> [--theme <name>] [--out <path>]` — render to stdout,
  or to `<path>` with `--out`.
- `BRAIN_EXPLAIN_LLM=ollama:<local-model> brain-explain theme new <name> --prompt "..."` — generate a norm-compliant theme. Choose the backend explicitly; no prompt is sent when it is unset. Only use a cloud model when you intend to send the prompt there.
- `brain-explain onboard` — first-run theme setup.

Personal theme setup and generation honour `AGENTBRAIN_VAULT` when the vault is external.

Themes: `clean-flat` (default), `editorial`, `whiteboard`, plus your own under
`vault/explainers/themes/`. The theme resolves as `--theme`, then the note's `theme:`
frontmatter, then `default_theme` in `vault/explainers/config.json`, then `clean-flat`.
The page's `lang` comes from the note's `lang:`, `language:` or `locale:` frontmatter,
else `en`.
