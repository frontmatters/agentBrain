---
date: 2026-06-04
type: system
tags: [skill, unpark]
id: 20175a38-553e-5caf-9cc1-e822ee2b65ed
---

# unpark

Load side of the see -> load -> save session loop.

## Purpose

In a fresh session, reloads a project's `index.md` plus all Related learnings, summarises status and open backlog, appends an "unparked" line to Progress, and starts executing the backlog. Project-level — not the same as `claude --resume`.

## Usage

```
/unpark <project-slug>
```

## Related

- [[park]] — counterpart that saves the session
- [[list-parks]] — find what is available to unpark
