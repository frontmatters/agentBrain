---
date: 2026-05-23
type: system
tags: [skill, peer-review, methodology, verification]
id: fe7654c8-2970-59c0-8927-638ae5cdeb2d
---

# `--help` grep ≠ smoke-test (verification methodology)

Grepping a CLI's `--help` output for a flag is **not** the same as proving that the exact invocation works.

Example: a CLI whose `--help` lists `-p` can still reject `tool -p -` at runtime with `Error: Unknown option: -`. The flag exists, the specific invocation does not.

**Rule**: before documenting or relying on an invocation (for example a new `--llm` backend in `bin/peer-review`), run that exact invocation against the real CLI. A `--help` grep is a necessary precondition, not a sufficient one.
