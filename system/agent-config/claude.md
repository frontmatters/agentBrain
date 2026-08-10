---
date: 2026-05-17
type: system
tags: [agent-config, claude]
id: aac2e385-d417-527a-a477-676dabb0e2f3
---

# Claude Agent Config

Claude/Claude Code reads `CLAUDE.md` as the tool-specific entrypoint.

## Recommended pointers

- Preference scopes: read any existing files under `${VAULT}/local/preferences/organization/`, `${VAULT}/local/preferences/team/`, and `${VAULT}/local/preferences/personal/`.
- **Daily note**: `${VAULT}/local/daily-notes/$(date +%F).md` (auto‑created by `ensure-daily-note.sh`)
- Self‑learning: write insights to the brain during sessions.

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Keep `CLAUDE.md` thin; detailed shared behaviour belongs here or in `shared.md`.
- Prefer updating existing notes over creating duplicates.
- Real learnings and project context go to `local/`, not public `learnings/`, unless explicitly sanitized for the public framework.

## Graphify (optional)

If the graphify add-on is enabled (`bash scripts/addons.sh status` shows
`graphify enabled`), prefer reading the knowledge graph over flat-file grep
for architecture questions that span more than ~5 files:

- Orient with `~/agentBrain/local/graphify-out/system/GRAPH_REPORT.md`
  (god nodes + surprising connections).
- Drill in with `jq` over `graph.json`.
- After framework edits, `bash system/addons/graphify/bin/brain-graph update`
  (AST-only, no API cost).

When the addon is not enabled, behave as before — grep remains the default.
