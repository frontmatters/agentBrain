---
date: 2026-05-20
type: skill
name: understand-project
description: Analyze any external project and store the knowledge graph in agentBrain
tags: [agentbrain, visualisation, understand-anything, project-analysis]
id: a58f3b2d-4c9e-5d0a-c2f3-6e7f8a9b0c1e
---

# /understand-project

Analyze any external project and store the knowledge graph in agentBrain.

## Prerequisites

- **Understand Anything** plugin installed
- Claude Max or equivalent high‑limit plan

## Usage

```
/understand-project ~/Developer/my-app
```

This scans the given project and stores the graph in:

```
local/projects/<project-name>/knowledge-graph/
├── knowledge-graph.json
└── meta.json
```

## How it works

1. Resolves the target path (must be a directory with a git repo)
2. Runs `/understand` on that directory
3. Copies the resulting `.understand-anything/` graph into agentBrain's project notes
4. Cleans up the graph from the target project (unless `--keep` is passed)

## Options

| Flag          | What it does                                                   |
| ------------- | -------------------------------------------------------------- |
| `--keep`      | Leave the graph in the target project as well as in agentBrain |
| `--full`      | Force full rebuild (ignore existing graph)                     |
| `--dashboard` | Open the dashboard after analysis                              |

## Use cases

1. **Before starting work on a new project** — understand the architecture first
2. **Legacy codebase onboarding** — generate a guided tour
3. **Refactoring planning** — understand dependencies before changing code
4. **Knowledge persistence** — store project understanding in agentBrain for future sessions

## Cost warning

Same as `/understand` — expensive on first run, incremental afterwards.
Only run when needed for projects you're actively working on.

## After analysis

The stored graph can be referenced by agents:

```markdown
See local/projects/my-app/knowledge-graph/knowledge-graph.json for architecture overview.
```

Re‑run `/understand-project` after significant changes to keep the graph fresh.
