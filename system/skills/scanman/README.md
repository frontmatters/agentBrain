---
date: 2026-05-31
type: skill
tags: [scanman, repo-distill, skill, agent-agnostic]
status: active
id: 86c9682c-a6fc-52d6-8ccd-527664b9dcdc
---

# Scanman

Agent-agnostic skill for distilling a repository's architecture into a canonical workspace with an enforced completeness gate.

## What it does

Given a repository path, scanman drives any agent (Claude Code, Pi, Copilot CLI, Gemini CLI) through a disciplined loop:

1. **Bootstrap** — generate file inventory, dependency map, system map, and runtime model skeleton (`scanman-init.sh` + `scanman-scan.sh`)
2. **Enrich** — the agent reads source files and fills `03-core-primitives.md`, `04-risk-and-bloat.md`, `05-redesign-v1.md` with `verified`/`inferred`/`unknown`-labeled content
3. **Validate** — `scanman-validate.sh` checks completeness via exit code; agent must iterate until it passes

The validation gate is pure bash + exit codes, so any agent that can run a shell command can follow the loop.

## Canonical workspace shape

```
local/research/repo-distill/<repo-slug>/
├── index.md
├── 00-file-inventory.md
├── 00b-dependency-map.md
├── 01-system-map.md
├── 02-runtime-model.md
├── 03-core-primitives.md
├── 04-risk-and-bloat.md
└── 05-redesign-v1.md
```

## Entry points

- `SKILL.md` — full method definition, agent loop, environment overrides, versioning policy
- `VERSION` — current method version (single source of truth, plain text)
- `CHANGELOG.md` — version history with rationale per change, plus the release-flow checklist

## Helper scripts

Located under `scripts/`:

- `scanman-init.sh <slug> <repo-path> [goal]` — create canonical workspace with frontmatter + UUIDs
- `scanman-scan.sh <repo-path> <slug>` — bootstrap layers 00/00b/01/02 (preserves enriched content)
- `scanman-refresh.sh <repo-path> <slug>` — re-run scan, keeping enriched docs intact
- `scanman-validate.sh <workspace-dir>` — mandatory completeness gate (exit 0 = pass, 1 = iterate, 2 = error)
- `scanman-bump-version.sh [patch] [--dry-run]` — version bumper (locked to 0.0.x)
- `scanman-compare.sh` — diff two workspaces
- `scanman-complete.sh` — convenience wrapper
- `scanman-release.sh` / `scanman-build-release.sh` — release tooling

## Templates

Under `templates/repo-distill-*.md` — copied by `scanman-init.sh` into the canonical workspace. The 03/04/05 templates include a `Claim Level` column so agents are visually seeded to fill `verified`/`inferred`/`unknown` per row.

## Why agent-agnostic matters

Every script is pure bash + python3 + standard tools. No Claude-only `Agent` tool calls, no MCP-specific functions, no sub-agent spawning. The same workspace and the same scripts work for every agent that can `bash` and `cat`.

See also: `local/learnings/agentbrain-artifacts-must-be-agent-agnostic.md` (the rule this skill follows).
