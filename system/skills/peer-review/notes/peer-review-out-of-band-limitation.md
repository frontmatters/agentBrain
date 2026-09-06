---
date: 2026-05-23
type: system
tags: [skill, peer-review, limitation, methodology]
id: d70aedd0-e26b-5971-998a-ccfa2aa9887b
---

# Out-of-band peer-review limitation

When `peer-review` is invoked from a chat session and the reviewer agent (e.g. Pi) runs out-of-band, the reviewer cannot see anything that happened in the calling chat — only the artifact passed in via the review request.

Concrete case: v1.1 chat verified 4 of 5 CLIs via `--help` smoke-tests inline. Pi's out-of-band review flagged all 5 as TBD because Pi never saw the chat-side verification. This is **expected behaviour**, not a Pi bug: out-of-band reviewers are deliberately context-isolated to keep reviews independent.

**Mitigation**: when chat-side verification matters to the review verdict, persist it into the artifact itself (e.g. an `AGENT_INVOCATION_VERIFIED_<name>=yes` block with the smoke-test command and output captured). See `../SPEC.md` §"v1.1 verification state".
