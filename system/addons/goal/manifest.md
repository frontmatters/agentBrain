---
id: goal
name: Goal
version: 0.1.0
author: frontmatters
install: none
command: bun
privacy: local
install_method: self
test: bun test tests/core.test.ts
support:
  pi: full
  claude: full
  copilot: unknown
  codex: unknown
  abh: unknown
outputs:
  - ~/.agentBrain/goal-logs/ (outside the vault; GOAL_LOG_DIR overrides)
---

# Goal

A goal is a verifiable stop-condition: an agent works until it is demonstrably
met, then it auto-clears. This addon holds the agent-neutral logic
(`lib/core.ts`) and the portable `ab-goal` CLI; the Pi extension
`system/pi-config/extensions/goal.ts` and the `/goal` skill are thin clients of
it. It ships with the core (see `scripts/lib/essential-addons.txt`) because a
shipped extension imports it: a registry-only addon there breaks a fresh
install's type-check.
