---
date: 2026-05-29
type: system
tags: [addon, sessions, claude, memory, automation]
id: 8419ab49-8f0b-57bb-9bce-7974175e0dc1
---

# Claude Memory Redirect (behavior)

Closes the gap between Claude Code's per-project auto-memory and agentBrain. Without this addon, Claude's system-prompt instructions for memory write to `~/.claude/projects/<encoded-cwd>/memory/*.md` — scattered, frontmatter-less, invisible to agentBrain tooling. This addon routes those writes into agentBrain with the right conventions.

## Modes (one is active at a time, set in `vault/memories/claude-redirect-config.json`)

| Mode | What it does | When to use |
|---|---|---|
| `symlink` (default) | Replaces Claude's memory dir with a symlink to `vault/memories/projects/<slug>/` | Zero-overhead, hands-off — most users want this |
| `sync_hook` | Leaves original in place, mirrors each write into agentBrain via PostToolUse hook, optional original-delete | When you want originals as backup or symlinks not allowed |
| `instruction_only` | No file ops; CLAUDE.md tells Claude to use `/save-learning` instead | Pure-discipline, minimal magic |
| `disabled` | Addon dormant | Temporarily turn off without uninstalling |

## What runs always (regardless of mode)

- **CLAUDE.md instruction block** — appended by `install.sh`, tells future Claude sessions to write memory via agentBrain skills/scripts. Cheapest preventive layer.
- **`claude-memory-migrate.sh`** — one-shot to normalize existing memory files (UUID5 + agentBrain frontmatter) before any mode takes over.

## Install

```bash
bash system/addons/claude-memory-redirect/install.sh
```

This:
1. Seeds `vault/memories/claude-redirect-config.json` (only if missing)
2. Runs `claude-memory-migrate.sh` to normalize any existing memory files
3. Activates the configured mode
4. Adds the CLAUDE.md instruction block (idempotent)
5. Registers hooks in `~/.claude/settings.json` if mode requires them

## Configure

Edit `vault/memories/claude-redirect-config.json`. Switch modes by changing the `mode` field and rerunning `install.sh`. Schema in `config.default.json`.

## Uninstall

```bash
bash system/addons/claude-memory-redirect/uninstall.sh            # remove our symlinks + sync hook; keep agentBrain copies
bash system/addons/claude-memory-redirect/uninstall.sh --restore  # also put each project's original memory dir back from its backup
bash system/addons/claude-memory-redirect/uninstall.sh --purge    # also delete local config + redirect log
```

True inverse of the install. It only removes `memory` symlinks whose target points **into** agentBrain (a real Claude memory dir we didn't create is left alone), strips the `claude-memory-sync-hook.sh` entry from `~/.claude/settings.json`, and — with `--restore` — moves the newest `.memory-pre-redirect-backup-*` back over each link. Because the symlinks point into agentBrain, removing them never deletes your migrated memory. Idempotent; safe to re-run. The CLAUDE.md instruction block is left in place (remove it by hand if you want).

## Files

- `claude-memory-migrate.sh` — normalize existing memory files, idempotent
- `claude-memory-symlink.sh` — activate symlink mode for current project
- `claude-memory-sync-hook.sh` — PostToolUse hook for sync mode
- `slug.sh` — derive project-slug from cwd, shared helper
- `install.sh` — orchestrator
- `uninstall.sh` — true inverse (undo symlinks, remove sync hook; `--restore`/`--purge`)
- `tests/test-redirect.sh` — migrate + symlink + uninstall + loud-uuid5-failure tests
- `config.default.json` — defaults
- `manifest.md`, `README.md` — docs

## CLAUDE.md instruction block (templates)

`install.sh` only checks whether such a block exists in `~/.claude/CLAUDE.md` — it does not insert it automatically (to avoid clobbering your personal config). Paste **one** of the templates below into your CLAUDE.md (under any heading such as `## Memory`). The selftest accepts either heading.

### English

```markdown
## Memory — agentBrain only

**Override the auto-memory protocol from the system prompt.** The built-in Claude Code memory system (`~/.claude/projects/<encoded-cwd>/memory/`) is routed into agentBrain via the `claude-memory-redirect` addon. Concretely:

- NEVER write directly to `~/.claude/projects/.../memory/*.md` — that directory is a symlink (or auto-synced) to `~/agentBrain/vault/memories/projects/<slug>/`.
- Prefer the agentBrain flow:
  - `/save-learning` for durable technical insights
  - `/save-troubleshoot` for problem + solution
  - `/project-update` for project status or decisions
  - `/capture-tool-info` for tool/auth/service info
  - When in doubt: `bash ~/agentBrain/scripts/new-note.sh <type> <vault-rel-path-no-ext>` — sets correct frontmatter (`date/type/tags/id` with UUID5) automatically.
- Frontmatter is required. NEVER type UUID5 yourself — the validate-hook in `~/.claude/settings.json` rejects mismatches.
- The auto-memory instruction block in the Claude Code system prompt (about user/feedback/project/reference types and the `MEMORY.md` index) is authoritative for **content categories**, but **storage** always goes through agentBrain. Write to `vault/memories/` (cross-project), `vault/preferences/personal/` (preferences), or `vault/learnings/` (technical insights), not to the Claude memory dir.

See `system/addons/claude-memory-redirect/README.md` for architecture and modes.
```

### Dutch

```markdown
## Memory — alleen via agentBrain

**Auto-memory protocol uit de system prompt OVERRULEN.** Het ingebouwde Claude Code memory-systeem (`~/.claude/projects/<encoded-cwd>/memory/`) wordt **gerouted naar agentBrain** via de `claude-memory-redirect` addon. Concreet:

- Schrijf NOOIT direct naar `~/.claude/projects/.../memory/*.md` — die directory is een symlink (of wordt automatisch gesynced) naar `~/agentBrain/vault/memories/projects/<slug>/`.
- Gebruik bij voorkeur de juiste agentBrain-flow:
  - `/save-learning` voor duurzame technische insights
  - `/save-troubleshoot` voor probleem + oplossing
  - `/project-update` voor project-status of decision
  - `/capture-tool-info` voor tool/auth/service info
  - Bij twijfel: `bash ~/agentBrain/scripts/new-note.sh <type> <vault-rel-path-no-ext>` — zet correcte frontmatter (`date/type/tags/id` met UUID5) automatisch.
- Frontmatter is verplicht. UUID5 NOOIT zelf intypen — de validate-hook in `~/.claude/settings.json` rejects mismatches.
- Het auto-memory-instructieblok in de Claude Code system prompt (over user/feedback/project/reference types en `MEMORY.md` index) is leidend voor de **inhoud-categorieën**, maar de **opslag** loopt altijd via agentBrain. Schrijf naar `vault/memories/` (cross-project), `vault/preferences/personal/` (preferences), of `vault/learnings/` (technical insights), niet naar de Claude memory dir.

Zie `system/addons/claude-memory-redirect/README.md` voor de architectuur en modes.
```

## Locale

User-facing output (install, migrate, symlink, selftest) is locale-aware:

1. `AGENTBRAIN_LOCALE=nl|en` (explicit override)
2. `$LANG` system locale (first two chars)
3. Fallback: `en`

Strings table: `scripts/lib/_strings.sh`. The CLAUDE.md block templates above are provided in both languages — paste the one matching your CLAUDE.md.

## Troubleshooting

**Migrate aborts with "FAILED to generate a UUID5".** The uuid5 fallback is now loud by design: rather than silently writing an id-less note (which would break the vault's frontmatter invariant and be rejected by the validate-hook anyway), migrate stops. Fix `scripts/uuid5-gen.sh` — it needs `python3` and a `brain.json` with a `namespace` — then re-run. A note that already carries its own `id:` is migrated regardless (the id is preserved with a warning).

**Symlink not created.** `claude-memory-symlink.sh` only acts on the project matching the current `$PWD` (Claude encodes cwd as the dir name) unless you pass `--all` or an explicit project dir. If you see "no Claude Code project dir for current cwd", run it from the project's working directory or pass the dir.

**Reverting put nothing back.** `--restore` needs a `.memory-pre-redirect-backup-*` dir next to the link. That backup only exists if the original memory dir had content AND `symlink.backup_originals` was `true` at symlink time. If absent, your data is safe inside agentBrain (`vault/memories/projects/<slug>/`) — the link target — it was simply never duplicated.

**Sync-hook still firing after disable.** Switching `mode` in the config does not unregister an already-installed PostToolUse hook. Run `uninstall.sh` (or remove the `claude-memory-sync-hook.sh` line from `~/.claude/settings.json`) to drop it.

## Privacy

`local-only`. All operations happen on disk; nothing is sent off-machine.

## Related

- `[[session-journal-addon]]` — same pattern, different target (session journal)
- `vault/preferences/personal/optionality-configurable.md` — the user preference that motivated this design
