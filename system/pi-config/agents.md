---
date: 2026-05-17
type: system
tags: [pi-agent, entry-point, agentbrain]
id: 6a696572-e097-58fd-a67b-c2cdf9845c51
---

# Pi Agent Instructions

This is the Pi entrypoint source. The bootstrap links it to `~/.pi/agent/AGENTS.md`.

Read and follow, in order:

1. `system/rules.md` — canonical public/private and write-location policy.
2. `system/agent-config/shared.md` — shared agent startup/checklist.
3. `system/agent-config/pi.md` — Pi-specific behaviour.

Key reminders:

- Public files describe HOW/WHERE; real user/project/security details go in `local/`.
- Before asking for credentials, check `local/integrations/` and `local/security/`.
- Public changes require `scripts/privacy-scan.sh`.
- Private local changes should be synced with `scripts/sync-agentbrain-local.sh`.
