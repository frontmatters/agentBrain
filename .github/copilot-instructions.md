---
date: 2026-05-17
type: system
tags: [meta, copilot-config, entry-point]
id: fa302a57-d7cd-5211-bed8-ebaa80df1fe3
---

# Copilot Instructions

This is the GitHub Copilot entrypoint for agentBrain.

Read and follow, in order:

1. `system/rules.md` — canonical public/private and write-location policy.
2. `system/agent-config/shared.md` — shared agent startup/checklist.
3. `system/agent-config/copilot.md` — Copilot-specific behaviour.

4. Read today’s daily note for context (e.g., `${VAULT}/local/daily-notes/$(date +%F).md`).

Key reminders:

- Public files describe HOW/WHERE; real user/project/security details go in `local/`.
- Before asking for credentials, check `local/integrations/` and `local/security/`.
- Public changes require `scripts/privacy-scan.sh`.
- Private local changes should be synced with `scripts/sync-agentbrain-local.sh`.
