---
date: 2026-05-20
type: skill
name: understand
description: Generate an interactive knowledge graph of the agentBrain codebase using Understand Anything
tags: [agentbrain, visualisation, understand-anything, codebase-map]
id: f47e2a1c-3b8d-5c9a-b1e2-4d5f6a7b8c9d
---

# /understand

Analyze the agentBrain codebase itself and produce an interactive knowledge graph.

## Prerequisites

- **Understand Anything** plugin installed (see below)
- Claude Max or equivalent high‑limit plan (token cost: ~25% of Claude Max for medium repos)

## Install Understand Anything

In Claude Code:

```
/plugin marketplace add Lum1104/Understand-Anything
/plugin install understand-anything
```

In Pi:

```
Fetch and follow instructions from https://raw.githubusercontent.com/Lum1104/Understand-Anything/refs/heads/main/.pi/INSTALL.md
```

## Usage

```
/understand
```

This scans the agentBrain repository at `${VAULT}` and produces:

- `.understand-anything/knowledge-graph.json` — the full graph
- `.understand-anything/meta.json` — analysis metadata

## Where the graph is stored

The graph is stored inside the repo at `.understand-anything/`. Add to `.gitignore`:

```
.understand-anything/intermediate/
.understand-anything/diff-overlay.json
```

Commit `knowledge-graph.json` and `meta.json` if you want teammates to skip the pipeline.

## Subsequent runs

After the first full scan, subsequent runs are **incremental** — only changed files are re‑analyzed. Force a full rebuild with:

```
/understand --full
```

## Dashboard

```
/understand-dashboard
```

Opens an interactive web dashboard with:

- Structural graph (files, functions, classes, relationships)
- Architectural layers (system, extensions, scripts, config, docs)
- Guided tour for onboarding
- Semantic search across the codebase

## Other commands

| Command                       | What it does                               |
| ----------------------------- | ------------------------------------------ |
| `/understand-chat <question>` | Ask anything about the agentBrain codebase |
| `/understand-diff`            | See impact of uncommitted changes          |
| `/understand-explain <file>`  | Deep‑dive into a specific file             |
| `/understand-onboard`         | Generate an onboarding guide               |

## Use cases for agentBrain

1. **New contributor onboarding** — `/understand-onboard` generates a guided tour
2. **Refactoring planning** — `/understand-diff` shows ripple effects before changes
3. **Architecture understanding** — Dashboard shows layers and dependencies
4. **AI agent context** — Graph provides structured knowledge for agents

## Cost warning

The initial analysis is expensive:

- ~30 minutes processing time
- ~25% of Claude Max rate limit
- Subsequent incremental runs are much cheaper

Only run when needed. Do not automate in every session.
