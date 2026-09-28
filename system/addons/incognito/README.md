---
date: 2026-06-16
type: system
tags: [addon, incognito, privacy, claude]
id: 900dc603-9f20-5629-a936-b77777f2729b
---

# incognito — read-only agentBrain sessions

Consult the brain, write nothing. Use it for throwaway experiments, sensitive
work, or any session you don't want to pollute the vault.

## Usage

```
/incognito on        # vault read-only: reads work, writes blocked
/incognito off       # writes enabled again
/incognito           # show status
```

Or the CLI directly: `bash system/addons/incognito/bin/incognito on|off|status`.

To **start** a session already incognito, create the flag before launching:

```bash
touch ~/agentBrain/vault/sessions/.incognito
```

The SessionStart hook then injects an incognito banner into the session context.

## How it works

State is one flag file: `<active-vault>/vault/sessions/.incognito`. It lives in
the active vault, so it flips with `brain use dev|live`.

Every write path checks the flag via `is-incognito.sh` and stops:

| Path | Hook / check | Behavior when incognito |
|------|------|-------------------------|
| Claude Code `Write/Edit/MultiEdit` to `vault/` notes | `claude-pretooluse-guard.sh` (PreToolUse) | exit 2 → write blocked before it happens |
| Pi `Write/Edit/MultiEdit` to `vault/` notes | `pi-config/extensions/incognito-guard.ts` (`tool_call`) | `{ block: true }` → write blocked before it happens |
| MCP `brain_save_learning` / `brain_project_update` | `assertNotIncognito()` in `agentbrain-mcp/src/write.ts` | throws → tool call fails (agent-agnostic) |
| Session start (flag pre-set) | `session-banner.sh` (wired into SessionStart) | injects a read-only banner into the session context |
| session-journal autosave / end (Claude) | `session-journal/claude-{autosave,stop}-hook.sh` | early exit 0 |
| session-journal (Pi) | `pi-config/extensions/session-continuity.ts` | early return, status "incognito (read-only)" |
| learning extraction (Claude) | `extract-learnings/claude-precompact-hook.sh` | early exit 0 |
| learning extraction (Pi) | `pi-config/extensions/extract-learnings.ts` | early return on `session_before_compact` / `session_shutdown` |
| (read) brain_search/read/recent | — | unaffected |

### Per-agent coverage

| Agent | Direct file writes | MCP write tools | journal / learning extraction |
|-------|--------------------|-----------------|-------------------------------|
| Claude Code | ✅ PreToolUse hook | ✅ MCP guard | ✅ Claude hooks |
| Pi | ✅ `incognito-guard.ts` | ✅ MCP guard | ✅ Pi extensions |
| Copilot CLI / others | ⚠️ behavioral only (no hook system) | ✅ MCP guard | n/a / behavioral |

Pi resolves the flag via `brain-paths.ts` (`isIncognito()`), the single Pi-side source
of truth, mirroring `is-incognito.sh` and the MCP guard.

### What is NOT mechanically blocked

For agents **with** a write-interception mechanism (Claude Code, Pi) enforcement covers
direct file writes, the MCP write tools, and the session hooks. For agents **without**
one (e.g. Copilot CLI), only the MCP write tools are hard-blocked — direct file writes
fall back to behavioral honoring (the `incognito` skill + the read-only note in
`system/agent-config/shared.md`).

Across all agents it does **not** intercept arbitrary `Bash` that writes into `vault/`
— e.g. `new-note.sh`, `echo >> note.md`, or a save-* script run from a shell. Those are
explicit shell actions and rely on the agent honoring incognito. If you need a hard
guarantee against shell or hook-less writes, make `vault/` read-only at the filesystem
level for the session.

Code edits (`system/`, `scripts/`, root config) stay allowed — incognito stops
**new knowledge**, not all work.

## Wiring

Two `~/.claude/settings.json` entries:

```json
// hooks.PreToolUse — block writes while incognito
{ "matcher": "Write|Edit|MultiEdit",
  "hooks": [{ "type": "command",
    "command": "~/agentBrain/system/addons/incognito/claude-pretooluse-guard.sh" }] }

// hooks.SessionStart — banner when a session starts already incognito
{ "matcher": "*",
  "hooks": [{ "type": "command",
    "command": "~/agentBrain/system/addons/incognito/session-banner.sh" }] }
```

`session-banner.sh` is agent-neutral (plain stdout) — other agents (Pi, Copilot,
Gemini) can call it from their own session-start hook instead of duplicating it.

The three early-exit checks are edits inside the existing session-journal /
extract-learnings hooks (no new settings.json entries needed for those).

Run `bash system/addons/incognito/install.sh` to verify wiring and `chmod +x`.
