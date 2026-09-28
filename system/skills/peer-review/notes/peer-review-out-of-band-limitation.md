---
date: 2026-05-23
type: system
tags: [skill, peer-review, limitation, methodology]
id: d70aedd0-e26b-5971-998a-ccfa2aa9887b
---

# Out-of-band peer-review limitation

A `peer-review` consumer runs out-of-band: it sees only the document carried in the `peer-review.review.requested` event, never the calling chat.

Example: the calling chat verifies a claim inline, and the reviewer still flags it as unverified because it never saw that verification. This is **expected behaviour**, not a reviewer bug: out-of-band reviewers are deliberately context-isolated to keep reviews independent.

**Mitigation**: when chat-side verification matters to the verdict, put it into the document itself (the command and its captured output) before requesting the review.
