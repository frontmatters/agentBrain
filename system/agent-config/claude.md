---
date: 2026-05-17
type: system
tags: [agent-config, claude]
id: aac2e385-d417-527a-a477-676dabb0e2f3
---

# Claude Agent Config

Claude/Claude Code reads `CLAUDE.md` as the tool-specific entrypoint.

## Recommended pointers

- Preference scopes: read any existing files under `${VAULT}/vault/preferences/organization/`, `${VAULT}/vault/preferences/team/`, and `${VAULT}/vault/preferences/personal/`.
- **Daily note**: `${VAULT}/vault/daily-notes/$(date +%F).md` (auto‑created by `ensure-daily-note.sh`)
- Self‑learning: write insights to the brain during sessions.

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Keep `CLAUDE.md` thin; detailed shared behaviour belongs here or in `shared.md`.
- Prefer updating existing notes over creating duplicates.
- Real learnings and project context go to `vault/`, not public `learnings/`, unless explicitly sanitized for the public framework.

## Graphify (optional)

If the graphify add-on is enabled (`bash scripts/addons.sh status` shows
`graphify enabled`), prefer reading the knowledge graph over flat-file grep
for architecture questions that span more than ~5 files:

- Orient with `~/agentBrain/vault/graphify-out/system/GRAPH_REPORT.md`
  (god nodes + surprising connections).
- Drill in with `jq` over `graph.json`.
- After framework edits, `bash system/addons/graphify/bin/brain-graph update`
  (AST-only, no API cost).

When the addon is not enabled, behave as before — grep remains the default.

## The `grep` in the Bash tool is not `/usr/bin/grep`

Claude Code wraps `grep` as a shell function that runs `ugrep --ignore-files`, so it
honours `.gitignore`. Verify it on the machine you are on:

```
type grep          # "grep is a shell function from ~/.claude/shell-snapshots/..."
type -f grep       # ARGV0=ugrep ... -G --ignore-files --hidden -I --exclude-dir=.git
```

The consequence is not a slower search but a wrong one, and it announces nothing:
exit 1, empty stdout, empty stderr. Indistinguishable from an honest zero. In a
directory whose `.gitignore` is fail-closed (`/*` with one exception), every
checkout below that root is invisible to the wrapper.

Follow the rule in `shared.md`: when the absence carries the conclusion, repeat with
`/usr/bin/grep`. `find` is unaffected and makes a good second measurement. For a
normal lookup the wrapper is fine, and faster.
