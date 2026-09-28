---
name: addons
description: Manage agentBrain addons via scripts/addons.sh. Use when the user asks about addons or extensions, says "which addons do I have", "enable/disable X", "install addon X", "configure X", or wants to manage scheduled jobs (launchd). Wraps the canonical addons.sh CLI. Also triggers on "addon status", "is X enabled", "edit X config", "extensions".
---

# Addons skill

Agent-agnostic wrapper around `scripts/addons.sh` for addon management inside agentBrain. Works for any agent that can invoke bash (Pi, Claude, Cursor, Gemini, Copilot, opencode, etc.).

## Location

```
~/agentBrain/scripts/addons.sh        # canonical CLI
~/agentBrain/system/addons/<id>/      # addon source (manifest + bin + templates)
~/agentBrain/vault/addons/<id>/       # per-machine state + user config
```

## Intent → command mapping

When the user asks about addons, map to the commands below. Don't manually edit `enabled` touch-files or `manifest.md`; always use `addons.sh`.

| User intent | Command |
|---|---|
| "which addons do I have" / "list addons" | `bash scripts/addons.sh status` |
| "is X enabled" / "is X active" | `bash scripts/addons.sh status` + read row |
| "install X" / "enable X" / "turn on X" | `bash scripts/addons.sh install <id>` |
| "disable X" / "turn off X" / "remove X" | `bash scripts/addons.sh disable <id>` |
| "configure X" / "edit X config" / "change X settings" | `bash scripts/addons.sh configure <id>` |
| "check X" / "is X healthy" / "does X still work" | `bash scripts/addons.sh check <id>` |
| "test addons" / "validate all" | `bash scripts/addons.sh test` |

## Commands reference

| Command | Effect |
|---|---|
| `status` | Table of all addons with state (available/enabled). |
| `install <id>` | Privacy gate → install command from manifest → enable → health check → (opt-in) launchd schedule. Full onboarding. |
| `enable <id>` | State-toggle only (does not touch schedule). |
| `disable <id>` | State-toggle off + uninstall launchd job if any. |
| `configure <id>` | Opens user config in `$EDITOR` (default `vi`). Auto-detects `vault/addons/<id>/*.{json,yaml,toml,conf}`; skips state/stats/lock/log files. |
| `check [<id>]` | Runtime health: is the manifest's `command:` prereq available? |
| `test [<id>]` | Static manifest validation + runtime health. |

## Schedule (launchd, macOS)

Addons with a `schedule:` block in their manifest can opt in to a launchd job. `install` prompts automatically. `disable` cleans up. For manual control:

```bash
bash scripts/setup/setup-addon-launchd.sh install|uninstall|kickstart|status <id>
```

Logs from scheduled runs land in `vault/logs/<id>.{out,err}.log` — not `/tmp/` (in-brain).

## Non-interactive flows (CI, scripts)

```bash
ADDONS_ASSUME_YES=1 bash scripts/addons.sh install <id>   # accept all prompts
ADDONS_DRY_RUN=1 bash scripts/addons.sh install <id>      # echo install cmd, don't run
```

## For agents: do's & don'ts

**Do**:
- Run `status` first to see current state before acting.
- When unsure about the addon id, show the status table to the user and ask which one.
- Use `install` for the full flow (privacy + install + enable + schedule) — not just `enable`.
- For non-TTY agents (scheduled flows): edit the file directly via Edit/Write tool using the path under `vault/addons/<id>/`, instead of `configure` which opens an editor.

**Don't**:
- Manually edit `manifest.md` or `enabled` state files.
- Invoke ad-hoc launchctl commands outside `setup-addon-launchd.sh`.
- Pass `ADDONS_ASSUME_YES=1` to `install` unless the user explicitly wants to skip the privacy gate — the gate exists for a reason.

## Privacy tiers

- `local` — nothing leaves the machine
- `local-only` — strict-local: nothing leaves the machine and outputs are meant to stay on it (per-machine state, secrets, recordings). Not a sync exclusion: `sync-vault.sh` commits the whole vault, so outputs inside it travel with a vault push unless the vault `.gitignore` excludes them
- `sends-docs` — notes/docs go to the configured LLM
- `sends-all` — docs AND code go to the LLM

## Known addons

Always verify with `bash scripts/addons.sh status` for the current list — this may go stale.

| ID | Purpose | Privacy | Schedule? |
|---|---|---|---|
| `weekly-review` | Weekly markdown summary of vault activity | sends-docs | Sunday 18:00 |
| `youtube-digest` | YouTube transcripts sync to `vault/youtube-digest/` | sends-docs | Every 6h |
| `event-bus` | Inter-agent communication transport | local | no |
| `extract-learnings` | Pi extension for auto-extraction | sends-docs | no |
| `agentbrain-mcp` | agentBrain MCP server | local | no |
| `session-journal` | Per-session journal addon | local-only | no |
| `anthropic-skills` | Anthropic official skills bundle | local | no |
| `trailofbits-skills` | Security skills bundle | local | no |
| `impeccable` | Frontend design skill | local | no |
| `graphify` | Knowledge graph visualisation | sends-docs | no |
| `routa` | Routing/navigation helper | sends-all | no |
| `understand-anything` | External-project understanding | sends-all | no |

## Example conversations

**User**: "which addons do I have enabled?"
**Agent**: `bash scripts/addons.sh status | grep enabled`

**User**: "turn on weekly-review"
**Agent**: `bash scripts/addons.sh install weekly-review`  *(schedule prompt follows; user picks y/n)*

**User**: "change my youtube channels"
**Agent**: `bash scripts/addons.sh configure youtube-digest`

**User**: "remove youtube-digest"
**Agent**: `bash scripts/addons.sh disable youtube-digest`  *(uninstall command lives in the addon's own scripts; manual cleanup may be needed)*

## References

- `system/tools.md` — overall agentBrain CLI registry
- `system/addons/*/manifest.md` — per-addon source-of-truth (id, install, privacy, schedule)
- `system/addons/*/README.md` — per-addon docs
- `scripts/setup/setup-addon-launchd.sh` — schedule framework (macOS launchd)
