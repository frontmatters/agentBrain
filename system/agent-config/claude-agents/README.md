---
date: 2026-07-08
type: system
tags: [agent-config, claude-code, model-routing]
id: ebd7408c-d4ef-5fca-be28-6ccce3a9c10c
---

# Claude Code subagents (model routing)

agentBrain-managed subagent definitions for Claude Code, implementing the
model-routing policy: frontier models plan and review, cheaper models execute.
The routing table itself lives in the private layer
(`local/preferences/personal/model-routing.md`); these files are the Claude
Code-specific execution of it.

| Agent | Model | Role |
|---|---|---|
| `executor` | sonnet | Implements an approved plan/spec; applies review feedback |
| `scout` | haiku | Read-only reconnaissance: find, list, summarize |

## Install

Symlink into Claude Code's agents directory (same pattern as skills — link via
the `~/agentBrain` alias so a dev/live checkout flip never breaks the link):

```bash
ln -sfn ~/agentBrain/system/agent-config/claude-agents/executor.md ~/.claude/agents/executor.md
ln -sfn ~/agentBrain/system/agent-config/claude-agents/scout.md ~/.claude/agents/scout.md
```

New agents are picked up at the next Claude Code session start.

## Format note

Each file carries two frontmatter schemas at once: Claude Code reads
`name`/`description`/`model`/`tools` and ignores the rest; agentBrain's
frontmatter check validates `date`/`type`/`tags`/`id`. Keep both when editing.
