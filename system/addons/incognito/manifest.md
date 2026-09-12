---
id: incognito
name: Incognito Mode (behavior)
version: 0.1.1
author: frontmatters
install: bash system/addons/incognito/install.sh
command: bash
# On by default in a fresh install; the user can untick it.
default_enabled: true
privacy: local-only
install_method: self
test: bash tests/test-incognito.sh
support:
  pi: none
  claude: full
  copilot: unknown
  codex: unknown
  abh: unknown
outputs:
  - vault/sessions/.incognito
---

# Incognito Mode (behavior add-on)

A session mode where agentBrain can still be **consulted** (reads) but **nothing
new is written** to it. For experiments, sensitive work, or keeping the vault clean.

Two layers, because agentBrain writes two ways:

- **Mechanical** — write-side paths check a flag and no-op:
  - Claude Code PreToolUse guard blocks agent `Write/Edit/MultiEdit` to `vault/` notes
  - Pi `incognito-guard.ts` extension blocks the same via `tool_call` (`{ block: true }`)
  - MCP `brain_save_learning` / `brain_project_update` throw via `assertNotIncognito()` (agent-agnostic — covers Copilot etc.)
  - session-journal + learning-extraction skip on both Claude (hooks) and Pi (extensions)
  - NOT covered: arbitrary `Bash` writes into `vault/` (e.g. new-note.sh), and direct file
    writes by agents without a hook system (e.g. Copilot CLI) — behavioral only
- **Behavioral** — the `/incognito` skill's output + the read-only note in
  `system/agent-config/shared.md` tell every agent it must not write; the SessionStart
  hook injects a banner when a session starts incognito.

Reads (`brain_search` / `brain_read` / `brain_recent`) are never touched.

Toggle with the `/incognito` skill or the `incognito` CLI (`on` / `off` / `status`).
State is a single flag file in the active vault: `vault/sessions/.incognito`.
