---
date: 2026-05-23
type: system
tags: [skill, peer-review, methodology, verification]
id: fe7654c8-2970-59c0-8927-638ae5cdeb2d
---

# `--help` grep ≠ smoke-test (verification methodology)

Discovered during Pi's review of `peer-review` v1.1: grepping a CLI's `--help` output for a flag is **not** the same as proving that the exact invocation works.

Concrete case: the registry pattern `pi -p -` was marked "verified via --help" because `-p` exists in the help-text. The runtime fails with `Error: Unknown option: -` — the flag exists, the specific invocation does not.

**Rule**: before flipping any `AGENT_INVOCATION_VERIFIED_<name>` to `yes`, a real smoke-test must execute the exact invocation against the live CLI. `--help` grep is a necessary precondition, not a sufficient one. See `../SPEC.md` §"TWO verification levels".
