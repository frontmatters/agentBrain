---
date: 2026-05-17
type: system
tags: [agent-config, shared]
id: e0ec2f19-20d7-5b49-a8e8-4d161ac9cda0
---

# Shared Agent Instructions

`system/rules.md` is canonical. If instructions conflict, follow `system/rules.md`.

## Incognito mode (read-only sessions)

If `local/sessions/.incognito` exists, the session is **read-only**: consult the
brain freely, but persist **nothing**. Skip every write below — no journal
archive/update, no learnings, no project notes, no memories. This is agent-neutral
and applies to *all* agents.

Claude Code and Pi also enforce this mechanically (a PreToolUse hook / a `tool_call`
guard extension) and the agentbrain MCP server blocks its write tools regardless of
agent. Agents without a write-interception mechanism (e.g. Copilot CLI) rely on this
instruction — so honor it; do not write while the flag is present. Toggle with the
`incognito` skill/CLI (`/incognito on|off`).

## Session start

1. Read the public framework hot set — the canonical list is **`system/rules.md` Step 1** (patterns, troubleshooting, rules, skills, lifecycle). Read `system/integrations/opensrc.md` too if working with any npm/PyPI/crates.io dependency.
2. Read private context when relevant:
   - Preference scopes, in order when present:
     - `local/preferences/organization/` — organization-wide rules/context
     - `local/preferences/team/` — team agreements/context
     - `local/preferences/personal/` — individual preferences/style
   - Treat the scopes as additive context. If they appear to disagree, surface the tension instead of silently inventing a rule.
   - `local/projects/[name]/index.md`
   - `local/memories/`
3. **Session continuity** — read and archive the session journal:
   - Read `local/sessions/session-journal.md` (if exists)
   - Briefly summarize to the user: where were we, what was the next step
   - Archive it → `local/sessions/archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>.md`
     - PID = 4 lowercase random hex chars (e.g. `openssl rand -hex 2`); if the target file exists, generate a new PID and retry
     - Generate UUID5 from the final archive path: `scripts/uuid5-gen.sh "local/sessions/archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>"`
     - Write with full frontmatter (`id`, `date`, `project`, `previous`)
   - Start a fresh `session-journal.md` with new timestamp
4. For credential/API/Gitea/GitHub/keychain tasks, check before asking for tokens:
   - `local/integrations/README.md`
   - relevant `local/integrations/*.md`
   - `local/security/README.md`
   - relevant `local/security/**/*.md`
5. Use documented secrets-helper/keychain helpers first.
6. Never print or persist token values.
7. **agentBrain self-update** — if the session context contains a line starting with `[agentBrain] An update is available`, ask the user whether to update; on a yes, run `scripts/brain-update.sh`. This is agent-neutral: the `ask` auto_update mode hands the decision to you (any consuming agent) because the session-start hook has no TTY of its own.

## Session continuity

Agent maintains `local/sessions/session-journal.md` for crash recovery and session continuity.

### During session

After each significant action, update `session-journal.md`:

- Project name
- Current task
- What's done (checklist)
- Next step
- Open questions / blockers

### Journal format

```yaml
---
date: YYYY-MM-DD
type: session-journal
tags: [session]
project: <name>
previous: <YYYYMMDD-HHMMSS-<pid> of archived session>
id: <UUID5>
status: active
---

# Session Journal

## Last updated: HH:MM

### Project: <name>
### Task: <what we're doing>

### Done
- [x] ...

### Files changed
- `path/to/file` — what changed

### Next step
-> ...

### Open questions
- ...
```

### Archive

- Location: `local/sessions/archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>.md` (PID = random 4-hex collision guard)
- Archived at session start (previous journal), never deleted
- Monthly subfolders keep listings manageable (~50-150 files per month)
- All links (`[[wiki-links]]`, UUID5 `id` in frontmatter) remain intact permanently

## Live connections — keys, not prompts

When connecting agentBrain to external data sources (calendar, email, project
management, CRM, finance, …), follow this permission model:

- **Scoped API keys** — give the agent the narrowest possible scope (e.g.
  read-only for transcripts, no-delete for email). Store keys in
  `local/security/` (never in public files). Reference them by name; never
  print values.
- **Keys, not prompts** — a prompt that says "don't send emails" is not a
  permission layer. If the agent has the key/auth to send, it may send. Strip
  the key entirely if the action must never happen.
- **Document what it can touch** — for each connection, write a one-liner in
  `local/integrations/<tool>.md`: what scope, what it can read/write/delete.
  This is the actual permission surface, auditable at any time.
- **Verify before automating** — run a capability manually (cadence=manual)
  until you trust the output. Only then schedule it.

Store integration notes under `local/integrations/`. See `system/security-guidance.md`
for the full credential-management policy.

## Write locations

- Public HOW/WHERE framework changes: public repo (`system/` incl. `system/skills/`, `templates/`, `scripts/`, `system/pi-config/`).
- Private WHAT/user/project/security details: `local/` only.

## Validation

- Public changes: run `scripts/privacy-scan.sh`.
- Private local changes: run `scripts/check-agentbrain-local.sh` or `scripts/sync-agentbrain-local.sh`.
