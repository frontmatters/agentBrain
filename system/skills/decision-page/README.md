---
date: 2026-09-09
type: system
tags: [skill, decision-page]
id: 9dfd77c7-ebfc-50be-a0ed-aa89f83ce4d3
---

# decision-page

Turns open product or design decisions into one local HTML page the owner can
see, compare and answer: per decision the current state, the advised proposal,
the alternatives considered, wireframes, pros and cons, a comparison table,
what was rejected and why, evidence links, persisted choices and a markdown
export that brings the answers back into the chat.

- `SKILL.md`: when to use it, hard rules, the ten steps.
- `template.html`: page skeleton (styles, mock idiom, choice blocks, script).
- `check.mjs`: headless render check (radios per decision, no horizontal
  scroll, no clipped text, screenshots).

Local file only, never published: decision pages carry confidential product
and client context.

## Two templates

- `template.html` with `check.mjs`, the option page: a handful of decisions, each
  with A/B/C/D cards, wireframes and a comparison table.
- `template-register.html` with `register.js`, the register page: ten to twenty
  small decisions from a gaplog or review, each with evidence provenance, two or
  three options and a multi-line note, plus a three-state theme switch.

Theme: use the client's brand when there is one; otherwise the house style
("Frontmatters flat", orange accent, Sentient + Instrument Sans). Swap only the
token block at the top.
