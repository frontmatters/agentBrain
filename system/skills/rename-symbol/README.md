---
date: 2026-09-17
type: system
tags: [skill, rename-symbol, refactoring, naming]
id: c4766bde-c1b8-52cc-a2dd-9ccf7e05545c
---

# rename-symbol

Rename a function, method, variable or key across a codebase without breaking the
things that are not code.

Use `/rename-symbol` when a name has to change everywhere and the symbol crosses
files. The skill separates code from copy from evidence, sizes the replacement to
how short the name is, and verifies by running and looking rather than by reading
the diff, because a leak into user-visible copy looks correct in a diff.

For agentBrain's own files and paths, use `/refactor-brain` instead.
