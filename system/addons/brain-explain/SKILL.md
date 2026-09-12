---
name: brain-explain
description: >-
  Render an agentBrain markdown note into a themed, self-contained HTML explainer (one source, swappable theme, enforced norms). Use to explain something visually, like a whiteboard sketch or a magazine article, or to build/regenerate an explainer page or a new theme. Triggers: "leg X visueel uit", "maak een explainer", "render explainer", "explain X visually", "brain-explain", "nieuw theme", "theme new".
---

# brain-explain — themed HTML explainers from markdown

Turns a markdown note (frontmatter + shortcodes + wikilinks) into a readable,
self-contained HTML page. Three layers: **content** (the markdown source, the
source of truth), **theme** (a CSS skin, free to choose), **page** (generated HTML, sugar
that is always regenerable). Quality norms (OKLCH, readable body, no uxray bans)
are enforced for every theme by `scripts/checks/check-explainers.sh`.

This is an **addon** with a CLI; this skill is the discoverable command surface.

## When to use

- You want to explain a concept visually as a standalone, shareable page.
- You want to (re)generate an explainer's HTML after editing its markdown source.
- You want a new personal theme described in one sentence (LLM-generated, norm-checked).

## Invocation

The addon ships at `system/addons/brain-explain/bin/brain-explain`:

```bash
# render a note to <slug>.html next to the source (theme: --theme > frontmatter > config > editorial)
bash system/addons/brain-explain/bin/brain-explain render <note.md> [--theme <name>] [--out <path>]

# generate a norm-compliant theme from a style description (needs an LLM backend)
bash system/addons/brain-explain/bin/brain-explain theme new <name> --prompt "<style>"

# first-run theme setup (LLM check, falls back to copy-clean-flat)
bash system/addons/brain-explain/bin/brain-explain onboard
```

Explainers live in `vault/explainers/<slug>/` (source `index.md` + rendered HTML),
grouped by the MOC at `vault/explainers/index.md`. Themes: `editorial` (default),
`whiteboard`, `clean-flat` in `system/explainers/themes/`, plus your own under
`vault/explainers/themes/`.

## Authoring a note

Frontmatter needs `type: explainer`, a `category` from `system/explainers/categories.txt`,
and a `theme`. Visual structure uses semantic shortcodes (not MDX): `:::layers`,
`:::cards`, `:::flow`, `:::callout`. Unknown shortcodes degrade to a blockquote, so
the source never breaks. Every explainer must be linked in the MOC.

READ `system/explainers/copy-norms.md` BEFORE writing any visible copy and apply it
while drafting, not as a fix-up. It is the single source of truth (STE-derived,
ten mechanical self-check rules: active voice, max 25-word sentences, one term per
concept, no filler). The norm gate enforces rule 6 (punctuation) and warns on
rule 2 (sentence length); the rest are author self-checks per sentence.

## Related

- Dogfood + reference render: `vault/explainers/brain-explain/`
- Design: `vault/specs/2026-06-21-brain-explain-design.md`
- Norm gate: `scripts/checks/check-explainers.sh`
