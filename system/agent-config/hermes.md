---
date: 2026-06-10
type: system
tags: [agent-config, hermes]
id: c9f1eccb-b878-5da9-9e9e-c77b77175166
---

# Hermes Agent Config

Hermes (nousresearch/hermes-agent) connects to agentBrain through three
channels; only the first is wired automatically by `scripts/setup-hermes.sh`.

## 1. Global pointer — `~/.hermes/SOUL.md` (automatic)

Hermes injects `SOUL.md` into every session. Setup APPENDS the standard
agentBrain pointer block there (marker-guarded, idempotent) — SOUL.md is the
user's personality file and is never overwritten. Honor `HERMES_HOME` when set.

Per-project: Hermes also loads `AGENTS.md` and `CLAUDE.md` from the working
directory — projects that already carry an agentBrain pointer in CLAUDE.md get
brain context in Hermes for free.

## 2. MCP tools (one command, recommended)

Hermes reads `mcp_servers` from `~/.hermes/config.yaml`. Register the brain
server via Hermes' own validated flow:

```bash
hermes mcp add agentbrain --command bun \
  --args "$HOME/agentBrain/system/addons/agentbrain-mcp/src/server.ts"
```

No bun on the host (common on Linux SBCs — Hermes itself is Python and does
not ship one)? The server has no Bun-specific APIs, so node works via `tsx`
(node 20 can't run `.ts` natively; install deps first):

```bash
(cd "$HOME/agentBrain/system/addons/agentbrain-mcp" && npm install --omit=dev)
hermes mcp add agentbrain --command npx \
  --args -y tsx "$HOME/agentBrain/system/addons/agentbrain-mcp/src/server.ts"
```

Verify either variant with `hermes mcp test agentbrain`.

This gives Hermes `brain_search`/`brain_read`/`brain_save_learning` etc.,
within the MCP scope boundary (no `local/security/`, biometrics or addon
configs).

## 3. Skills (manual, review first)

Hermes ships its own skills with a different SKILL.md shape
(Overview/Prerequisites/Inputs/Workflow/Tools Reference/Tips). agentBrain
skills are not symlinked automatically — port individual skills only when
useful, adapting to Hermes' shape.

## Not yet integrated (known opportunities)

- **Memory providers** — Hermes has bounded built-in memory
  (`~/.hermes/memories/MEMORY.md` + `USER.md`, char-capped, injected each
  session) plus a plugin system for one external memory provider (Honcho,
  Mem0, …). An agentBrain provider — analogous to the `claude-memory-redirect`
  add-on — would be the deep integration; today Hermes' own memory and the
  brain live side by side.
- **Hooks** — Hermes has a hooks system (`~/.hermes/hooks/`); nothing from
  agentBrain (session-journal, extract-learnings) is wired into it.

## Hermes-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Hermes scans context files for prompt injection and truncates large ones —
  keep the SOUL.md pointer block short (it is); never inline brain content.
- Undo: remove the `## agentBrain` block from `~/.hermes/SOUL.md` and run
  `hermes mcp remove agentbrain`.
