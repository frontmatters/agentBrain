---
date: 2026-07-21
type: system
tags: [llm, prompt-caching, guidelines, agent-agnostic]
id: 513a2975-8c7b-5d2b-ae55-d11ba3744ce2
---

# LLM prompt composition — cache-aware guidelines

Prompt caching happens at the **provider** (OpenAI/Anthropic/...), not in the
harness or in agentBrain. The only lever agentBrain controls is **prefix
stability**: identical request-prefixes are re-used at a ~90% discount within
the provider's TTL; any change to the prefix (model, reasoning level, skills,
MCP definitions, system-prompt content) forces full re-computation.

Four rules for anyone writing agentBrain content that ends up in a prompt
prefix (skills, `AGENTS.md`, `system/rules.md`, agent-configs, addon system
prompts):

1. **Keep skill- and bootstrap-order static within a session.** The load order
   of the `AGENTS.md` chain (`rules.md → shared.md → agent-specific.md`) must
   not vary per session.
2. **Put dynamic content at the bottom of the prefix.** Dates, request IDs,
   session state and similar volatile values belong in the user-prompt layer,
   not in the system-prompt layer.
3. **Avoid mid-session skill/MCP toggles.** Enabling or disabling a skill,
   MCP server, or addon during a session changes the prefix and costs a cache
   miss. Toggle between sessions or after a `clear` instead. The same applies
   to switching model or reasoning level.
4. **For agentBrain's own LLM calls** (yt-digest summarizer, peer-review,
   brain-explain): stable instructions first, volatile input (transcript,
   document, message) after it. Batch identical-prefix calls back-to-back so
   they land within the provider's TTL.

Rationale, TTL table and break-trigger details:
`local/learnings/prompt-caching-mechanism-and-breaks.md` (private).
Design context: `local/backlog/2026-07-20-prompt-caching-awareness-design.md`.

## Validation

`scripts/check-prompt-cache-hygiene.sh` lints framework-owned prompt sources
for high-confidence volatile placeholders outside fenced and inline code. It is
a narrow policy check, not runtime cache detection. Run its fixture suite with
`scripts/test-prompt-cache-hygiene.sh`; the checker is also wired into doctor.
