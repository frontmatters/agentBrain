---
date: 2026-05-17
type: system
tags: [meta, claude-code, entry-point]
id: 1f6bcba0-ded7-579c-8a17-163e7f45dfb7
---

# Claude Instructions

This is the Claude/Claude Code entrypoint for agentBrain.

Read and follow, in order:

1. `system/rules.md` — canonical public/private and write-location policy.
2. `system/agent-config/shared.md` — shared agent startup/checklist.
3. `system/agent-config/claude.md` — Claude-specific behaviour.

Key reminders:

- Public files describe HOW/WHERE; real user/project/security details go in `local/`.
- Before asking for credentials, check `local/integrations/` and `local/security/`.
- Public changes require `scripts/privacy-scan.sh`.
- Private local changes should be synced with `scripts/sync-agentbrain-local.sh`.
