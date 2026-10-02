---
date: 2026-05-26
type: system
tags: [meta, tools, cli, index, warm]
id: bb1ddaf8-4f63-5295-bccc-ff2c2c2eb46f
---

# Tools

Index of bash CLIs and addon binaries in agentBrain. Skills (`/command` style) live in [`skills.md`](skills.md). This file is for **operations tools** — what to run when, from a shell.

> Path-conventions: `S` = `scripts/<name>.sh` (run as `bash $BRAIN_DIR/scripts/<name>.sh`), `A` = `system/addons/<id>/bin/<name>` (addon CLIs). The shorthand keeps the index compact.

## Daily operations

| Tool | Path | What it does |
|---|---|---|
| `brain` | `S brain.sh` | Flip the active framework checkout: `brain status`, `brain use dev`, `brain use live`, `brain version`. Installed on PATH as `brain` by `setup.sh`. |
| `brain tool-update` | `S tool-update.sh` | Stage and check a versioned agent CLI before atomically switching its command link; `status` counts old/new processes, `finish` waits for old sessions, `rollback` restores the link. Profiles: `system/tool-profiles/`. |
| `brain doctor` | `S doctor.sh --user` | Health check of your install and vault (the user checks). Exit 0 = healthy, non-zero = at least one check failed. Use `--summary` for compact output. In a source checkout, `doctor.sh` without `--user` (or `brain doctor --dev`) is the full framework audit with the `test-*.sh` suites; an installed release refuses it and points to `brain doctor`. |
| `smoke-test` | `S smoke-test.sh` | End-to-end behavioural verification (flip + Pi resolution + event-bus roundtrip + doctor in both checkouts). Non-destructive — restores flip state on exit. Use after deploy/refactor. |
| `new-note` | `S new-note.sh <type> <vault-rel-path-no-ext> [title]` | Create a note with correct frontmatter + computed UUID5. **Always use this — never type id by hand.** Types: learning, project, backlog, feedback, reference, session, spec. `--space <slug>` / `--context <slug>` writes into a sealed `vault/spaces/<slug>/` compartment; `--from <repo-or-file>` infers context when the harness CWD is elsewhere. Conflicting owner signals fail closed. Writes also auto-route by CWD code-root (see `docs/spaces.md`). To create a space itself, use `new-space`. |
| `uuid5-gen` | `S uuid5-gen.sh "<vault-rel-path-no-ext>"` | Generate deterministic UUID5 for a note path (uses `brain.json["namespace"]`). Used internally by `new-note.sh` + template rendering. |
| `new-space` | `S new-space.sh <slug> --owner "<name>" --relation <rel>` | Scaffold a sealed space passport (`vault/spaces/<slug>/index.md`) with a fresh `space-id` + path-derived `id`. Then set `sync:` and run `sync-space`. |
| `sync-space` | `S sync-space.sh <slug>` | Seal + back up ONE space to its OWN private remote (from the passport `sync:`); never the personal vault, never public. `sync: none` = local-only. |
| `build-space-map` | `S build-space-map.sh` | Regenerate `vault/.space-map.json` (slug ↔ aliases ↔ code-roots) that context inference reads. |
| `check-space-boundary` | `S check-space-boundary.sh` | Doctor gate: fail if a space `owner` name leaks into any public artifact. |

> **Spaces routing:** writes route into a space per-write via **context inference**
> (`system/lib/context.sh`) — CWD code-root, `AGENTBRAIN_CONTEXT=<slug>`, or an
> explicit `--context <slug>`. The old `active-space` session mode / `.active-space`
> marker is **decommissioned**. Full workflow: `docs/spaces.md`.

### Safe CLI update sequence

A package manager replaces a tool's files under running sessions, and a session that loads a module after that can die. `brain tool-update` installs the new version beside the old one and moves only the command's symlink. Where things are at each step, for Pi going from 0.87.1 to 0.99.2 (paths for other tools come from their profile):

| Step | `pi` command points at | Global install (`~/.bun/install/global/...`) | Staged copy (`$TOOL_VERSIONS_HOME/pi/0.99.2`) | Running sessions |
|---|---|---|---|---|
| before | global, 0.87.1 | 0.87.1 | none | 0.87.1 |
| `stage 0.99.2` | global, 0.87.1 | 0.87.1 | installed | unchanged |
| `check 0.99.2` | global, 0.87.1 | 0.87.1 | checked: profile checks, and a session copy exported by both versions with equal entry counts | unchanged |
| `switch 0.99.2` | staged copy, 0.99.2 | 0.87.1, kept for the old sessions | in use by new sessions | old ones stay on 0.87.1; new ones start on 0.99.2 |
| `status` | (counts only) | | | sessions started before and after the switch |
| `finish` (refuses while any pre-switch session runs) | global, now 0.99.2 | updated to 0.99.2 | removed if no session runs from it, else kept | sessions started after the switch keep running from the staged copy |
| `prune` (refuses while any session started before the finish runs) | global, 0.99.2 | 0.99.2 | removed | all on the global 0.99.2 |

- `rollback` (while switched) points the command back at the recorded previous target; the staged copy stays until you remove it.
- `switch` sets a reminder "Finish <tool> tool update" two days out; a `finish` that keeps the staged copy sets "Prune <tool> tool update". Each command closes its own reminder.
- Do not run the tool's own updater (`pi update`, `npm i -g`, `brew upgrade`) while switched: it updates the global install, not the version the command runs.
- Versions live under `TOOL_VERSIONS_HOME` (default `~/.local/share/tool-versions`), one directory per tool and version with its `state.json`. Profiles: `system/tool-profiles/`. For brew, never run `brew cleanup` on a keg an active session uses; brew can stage only the version its formula currently offers.
- `--force` on `finish` bypasses the active-process guard and should be used only after verifying no sessions depend on the old version.

`adopt <version> <previous-link-file>` records an already-switched tool without reinstalling or relinking it.

## Event-bus (inter-agent communication)

| Tool | Path | What it does |
|---|---|---|
| `brain-emit` | `A event-bus/bin/brain-emit` | Publish event to the bus. `--type=<topic> --to=<agent>\|--broadcast --payload=<json>`. Returns event_id. |
| `brain-poll` | `A event-bus/bin/brain-poll` | Read events matching this agent. `--agent=<name> --type=<glob> --lookback=<dur>`. Maintains a per-agent cursor. |
| `brain-ping` | `A event-bus/bin/brain-ping` | Built-in smoketest — emit a `system.bus.ping` and wait for `system.bus.pong`. |

See [`system/addons/event-bus/SPEC.md`](addons/event-bus/SPEC.md) for protocol details.

## YouTube Digest (ingestion add-on)

A registry add-on: install it with `bash scripts/addons.sh install youtube-digest`.

Pulls YouTube transcripts into the brain. **Two front-ends sharing one pipeline**: `sync` for configured channels, `fetch` for ad-hoc single URLs. All commands via `bun A youtube-digest/bin/yt-digest <command>`.

| Command | What it does |
|---|---|
| `sync [channel] [--all\|--max=N]` | Iterate configured channels (`vault/addons/youtube-digest/channels.json`), fetch latest N videos per channel, dedup against `state.json`. No-arg = all channels (cron-friendly). |
| `fetch <url\|id> [--category=X] [--tags=a,b]` | Single video, ad-hoc — no channel-list, no filtering. Synthesizes a channel-record from `--category` (default `ad-hoc`). Marks state so a later `sync` won't re-fetch. |
| `learn` | Extract learnings from saved transcripts → `vault/learnings/extracted/*.md`. |
| `list` | Show configured channels + priorities. |
| `status` | Show last-sync timestamp + processed-video count. |

**Pipeline (shared between sync + fetch)**: URL → `yt-dlp` metadata → `yt-dlp` transcript (`transcript_languages: ["en","nl"]`) → `summarizer.ts` (configurable LLM endpoint, fallback Pi active model) → markdown writer → `~/.agentBrain/vault/youtube-digest/<category>/<channel>/<year>/<date>-<slug>-<videoId>.md`.

**Private state**: `~/.agentBrain/vault/addons/youtube-digest/{channels.json, state.json, stats.json, logs/}`.

**Prereqs**: `bun` (runtime) + `yt-dlp` (`brew install yt-dlp`).

After install, `system/addons/youtube-digest/SKILL.md` has the usage details.

## Weekly Review (digest add-on)

A registry add-on: install it with `bash scripts/addons.sh install weekly-review`.

Generates a weekly markdown summary of vault activity. Hybrid source: aggregates
`vault/daily-notes/*.md` within the target ISO-week, supplemented by an mtime-scan of
`vault/{learnings,references,projects,backlog,sessions}`. Optional `git log` per
configured repo. Fixed LLM model for week-over-week consistency.

| Command | What it does |
|---|---|
| `weekly-review` | Current ISO-week, default config. |
| `weekly-review --last` | Last completed Mon-Sun (use for the Sunday cron). |
| `weekly-review --week=YYYY-WNN` | Specific week, e.g. `2026-W21`. |
| `weekly-review --dry-run` | Show what would be collected, skip LLM + write. |
| `weekly-review --no-llm` | Collect + write, raw lists only (no synthesis). |

CLI: `bash system/addons/weekly-review/bin/weekly-review [flags]`.

**Output**: `vault/sessions/weekly/<YYYY-WNN>.md` with frontmatter (date, week, range,
source counts, model used).

**Private config**: `~/.agentBrain/vault/addons/weekly-review/config.json` (LLM model,
scope-paths, git-roots).

**Prereqs**: `bash`, `jq`, `python3`, `ollama` CLI. Optional: `git` for activity log.

After install, `system/addons/weekly-review/README.md` covers launchd setup and
troubleshooting.

## Setup / install / configuration

| Tool | Path | What it does |
|---|---|---|
| `setup` | `S setup.sh` | Orchestrator — installs agent connectors for every detected AI tool. Idempotent. `--yes` for non-interactive. `--home=PATH` for sandbox/CI. |
| `bootstrap-macos` | `S installer/bootstrap/macos.sh` | First-time macOS setup: prereqs + setup.sh + configure-pi. |
| `install-prerequisites` | `S install-prerequisites.sh` | Install required dependencies (bun, jq, etc.). |
| `configure-pi` | `S configure-pi.sh` | (Re-)configure Pi extensions, skills, and tsconfig.json. **Run after Pi updates** if `check-pi-extension-types` starts failing. |
| `setup-<client>` | `S setup-{claude-code,cline,copilot,cursor,gemini-cli,hermes,opencode,devin,copilot-cli}.sh` | Per-client connectors. Each installs or refreshes a managed pointer block when its content changes; embedded blocks preserve user text and get a backup. `check-installed-pointers.sh` reports installed state in the user doctor. |
| `setup-abh-autostart` | `S setup-abh-autostart.sh enable|disable|status` | Optional user-level ABH Web startup: launchd on macOS, systemd --user on Linux/WSL. |

## Note + content management

| Tool | Path | What it does |
|---|---|---|
| `validate-note-id` | `S validate-note-id.sh <path>` | Verify a note's `id` matches `uuid5-gen.sh` for its path. Empty output = pass. |
| `ensure-daily-note` | `S ensure-daily-note.sh` | Create today's daily note from `templates/daily.md` (renders `{{date}}` + `{{uuid5}}`). Idempotent. Called by `loop-tick.sh`. |
| `update-daily-note` | `S update-daily-note.sh` | Append session info to today's daily note. |
| `update-startup-context` | `S update-startup-context.sh` | Regenerate `vault/sessions/startup-context.md` (due queue reminders first, then open findings). Called by `loop-tick.sh` and session-start integrations. |
| `loop-tick` | `S loop-tick.sh` | Autonomous tick: doctor + capture-findings + update-startup-context + ensure-daily-note. Run by launchd (`dev.agentbrain.loop`). |
| `capture-findings` | `S capture-findings.sh` | Serialize doctor warnings/errors to `vault/findings/<detector>.json` for MCP brain_findings_list. |

## Release / deploy

Maintainer release and deployment commands are not part of the public install.
Use the release workflow in the development checkout; do not expect these
commands in a downloaded archive.

## Add-on management

| Tool | Path | What it does |
|---|---|---|
| `addons.sh` | `S addons.sh` | Add-on registry CLI: `status`, `check`, install/enable/disable per addon. See [`system/addons/README.md`](addons/README.md). |

## Maintenance / migrations

| Tool | Path | What it does |
|---|---|---|
| `move-agentbrain` | `S move-agentbrain.sh` | Relocate the agentBrain checkout to a new path. |
| `offboard` / `import-offboard` | `S` | Export user content for portability / re-import. |
| `sync-vault` | `S sync-vault.sh [--dry-run] [message]` | Sync `vault/` and nested spaces to their private remotes. `--dry-run` and `--help` are side-effect free. |
| `privacy-scan` | `S privacy-scan.sh` | Scan public files for accidentally-leaked private content (run before any `system/` push). |
| `uninstall` | `S uninstall.sh` | Remove agentBrain connectors from agent configs (does not delete vault). |

## Quality checks (run via `doctor`, but standalone-capable)

Each lives in `scripts/checks/check-*.sh` and is invoked by `doctor.sh`; all are standalone-runnable when investigating a specific failure. They cover schema (`check-frontmatter`, `check-links`, `check-readmes`, …), architecture/docs truth (`check-architecture`, `check-skills-index`, `check-path-naming`, …), skills (`check-skill-links`, `check-skill-relations`, …), addons/extensions (`check-addons`, `check-pi-lens`, …), bootstrap/config (`check-version`, `check-client-pointers`, …), and knowledge quality (`check-brain-review`). The authoritative list is `ls scripts/checks/check-*.sh`. A release ships the checks that test an install; the checks that test the framework itself stay in the source checkout; each script documents itself in its header comment (see also [`scripts/README.md`](../scripts/README.md)).

Test scripts (`scripts/tests/test-*.sh`) verify individual subsystems. They are part of the source checkout, not of a release.

## Hooks (called by external triggers, not user-invoked)

- `claude-code-validate-note-id-hook.sh` — PostToolUse hook for Claude Code (validates ids written via Write/Edit).
- `setup-launchd-loop.sh` — installs the launchd job for `loop-tick`.
- `setup-git-hooks.sh` — installs git pre-commit hooks.

## Where this file lives in the context tiers

This file is **warm** — load on demand when doing shell-level operations, not at session start. The canonical hot startup set lives in `system/rules.md` (Self-Learning Protocol, Step 1). This file is intentionally an *index*, not a manual; full usage per tool is `--help` or the script header.

Token budget: ~600 tokens. Adding a new tool: one row in the right category. If the table grows past 1500 tokens, demote less-common tools to warm tier (or to per-category sub-docs).

## Related

- [`skills.md`](skills.md) — `/command` skills (different concept; this file is for bash tools)
- [`rules.md`](rules.md) — canonical write-location + public/private policy
- [`lifecycle.md`](lifecycle.md) — release / deploy / sync lifecycle stages
- [`addons/README.md`](addons/README.md) — addon system overview
