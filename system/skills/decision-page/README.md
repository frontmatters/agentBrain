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
