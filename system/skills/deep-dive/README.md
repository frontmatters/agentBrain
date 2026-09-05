---
date: 2026-08-14
type: system
tags: [skill, deep-dive]
id: 5610c38a-5b76-57c2-935e-0b5f8b875dfa
---

# deep-dive

Produce a DEEP, evidence-checked tutorial on a topic — not a summary one-pager.

## Purpose

For every claim it runs a What/Why/Where/How/When interrogation loop, hunts down
concrete evidence (real file paths, commands, code, numbers), flags anything still
vague, and resolves it before writing. Then it renders themed HTML by handing off
to the `brain-explain` skill (never hand-rolling a renderer).

Use when the user wants something thorough — "not a one-pager", "go deeper", "make
it a real tutorial", a handbook, masterclass, runbook, or training guide.

## Usage

```
/deep-dive <topic>
```

## Dependency

Requires the `brain-explain` skill (shipped as a system addon) for rendering.
