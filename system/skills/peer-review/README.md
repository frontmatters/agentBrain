---
date: 2026-05-31
type: skill
tags: [skill, peer-review, event-bus, agentbrain]
status: active
id: 5d9ec287-a393-5095-8dc5-0f1a0cbd8eeb
---

# peer-review

Async cross-agent review of any document via the agentBrain event-bus.

Emits `peer-review.review.requested`; any consumer agent (running as listener with any LLM backend) emits `peer-review.review.completed`. Caller can return immediately and poll later, or `--wait` for the first verdict. The review backend follows the cascaded config: `--llm`, then `PEER_REVIEW_DEFAULT_LLM`, then `vault/config/llm.json`, then a local ollama model; there is no cloud default.

Triggers: "peer-review", "let X review", "second opinion", "external review", "have another model check this".

See `SKILL.md` and `SPEC.md` for the full protocol.
