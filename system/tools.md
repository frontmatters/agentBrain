---
date: 2026-05-26
type: system
tags: [meta, tools, cli, index, hot]
id: bb1ddaf8-4f63-5295-bccc-ff2c2c2eb46f
---

# Tools

Index of bash CLIs and addon binaries in agentBrain. Skills (`/command` style) live in [`skills.md`](skills.md). This file is for **operations tools** — what to run when, from a shell.

> Path-conventions: `S` = `scripts/<name>.sh` (run as `bash $BRAIN_DIR/scripts/<name>.sh`), `A` = `system/addons/<id>/bin/<name>` (addon CLIs). The shorthand keeps the index compact.

## Daily operations

| Tool | Path | What it does |
|---|---|---|
| `brain` | `S brain.sh` | Flip the active framework checkout: `brain status`, `brain use dev`, `brain use live`, `brain version`. Installed on PATH as `brain` by `setup.sh`. |
| `doctor` | `S doctor.sh` | Framework health audit — runs all `check-*.sh` + `test-*.sh`. Exit 0 = healthy, non-zero = at least one check failed. Use `--summary` for compact output. |
| `smoke-test` | `S smoke-test.sh` | End-to-end behavioural verification (flip + Pi resolution + event-bus roundtrip + doctor in both checkouts). Non-destructive — restores flip state on exit. Use after deploy/refactor. |
| `new-note` | `S new-note.sh <type> <vault-rel-path-no-ext> [title]` | Create a note with correct frontmatter + computed UUID5. **Always use this — never type id by hand.** Types: learning, project, backlog, feedback, reference, session, spec. |
| `uuid5-gen` | `S uuid5-gen.sh "<vault-rel-path-no-ext>"` | Generate deterministic UUID5 for a note path (uses `brain.json["namespace"]`). Used internally by `new-note.sh` + template rendering. |

## Event-bus (inter-agent communication)

| Tool | Path | What it does |
|---|---|---|
| `brain-emit` | `A event-bus/bin/brain-emit` | Publish event to the bus. `--type=<topic> --to=<agent>\|--broadcast --payload=<json>`. Returns event_id. |
| `brain-poll` | `A event-bus/bin/brain-poll` | Read events matching this agent. `--agent=<name> --type=<glob> --lookback=<dur>`. Maintains a per-agent cursor. |
| `brain-ping` | `A event-bus/bin/brain-ping` | Built-in smoketest — emit a `system.bus.ping` and wait for `system.bus.pong`. |

See [`system/addons/event-bus/SPEC.md`](addons/event-bus/SPEC.md) for protocol details.

## YouTube Knowledge (ingestion add-on)

Pulls YouTube transcripts into the brain. **Two front-ends sharing one pipeline**: `sync` for configured channels, `fetch` for ad-hoc single URLs. All commands via `bun A youtube-knowledge/bin/yt-knowledge <command>`.

| Command | What it does |
|---|---|
| `sync [channel] [--all\|--max=N]` | Iterate configured channels (`local/addons/youtube-knowledge/channels.json`), fetch latest N videos per channel, dedup against `state.json`. No-arg = all channels (cron-friendly). |
| `fetch <url\|id> [--category=X] [--tags=a,b]` | Single video, ad-hoc — no channel-list, no filtering. Synthesizes a channel-record from `--category` (default `ad-hoc`). Marks state so a later `sync` won't re-fetch. |
| `learn` | Extract learnings from saved transcripts → `local/learnings/extracted/*.md`. |
| `list` | Show configured channels + priorities. |
| `status` | Show last-sync timestamp + processed-video count. |

**Pipeline (shared between sync + fetch)**: URL → `yt-dlp` metadata → `yt-dlp` transcript (`transcript_languages: ["en","nl"]`) → `summarizer.ts` (configurable LLM endpoint, fallback Pi active model) → markdown writer → `~/.agentBrain/vault/youtube-knowledge/<category>/<channel>/<year>/<date>-<slug>-<videoId>.md`.

**Private state**: `~/.agentBrain/vault/addons/youtube-knowledge/{channels.json, state.json, stats.json, logs/}`.

**Prereqs**: `bun` (runtime) + `yt-dlp` (`brew install yt-dlp`).

See [`system/addons/youtube-knowledge/SKILL.md`](addons/youtube-knowledge/SKILL.md) for usage details.

## Weekly Review (digest add-on)

Generates a weekly markdown summary of vault activity. Hybrid source: aggregates
`daily-notes/*.md` within the target ISO-week, supplemented by an mtime-scan of
`local/{learnings,references,projects,backlog,sessions}`. Optional `git log` per
configured repo. Fixed LLM model for week-over-week consistency.

| Command | What it does |
|---|---|
| `weekly-review` | Current ISO-week, default config. |
| `weekly-review --last` | Last completed Mon-Sun (use for the Sunday cron). |
| `weekly-review --week=YYYY-WNN` | Specific week, e.g. `2026-W21`. |
| `weekly-review --dry-run` | Show what would be collected, skip LLM + write. |
| `weekly-review --no-llm` | Collect + write, raw lists only (no synthesis). |

CLI: `bash system/addons/weekly-review/bin/weekly-review [flags]`.

**Output**: `local/sessions/weekly/<YYYY-WNN>.md` with frontmatter (date, week, range,
source counts, model used).

**Private config**: `~/.agentBrain/vault/addons/weekly-review/config.json` (LLM model,
scope-paths, git-roots).

**Prereqs**: `bash`, `jq`, `python3`, `ollama` CLI. Optional: `git` for activity log.

See [`system/addons/weekly-review/README.md`](addons/weekly-review/README.md) for
launchd setup + troubleshooting.

## Setup / install / configuration

| Tool | Path | What it does |
|---|---|---|
| `setup` | `S setup.sh` | Orchestrator — installs agent connectors for every detected AI tool. Idempotent. `--yes` for non-interactive. `--home=PATH` for sandbox/CI. |
| `bootstrap-macos` | `S bootstrap-macos.sh` | First-time macOS setup: prereqs + setup.sh + configure-pi. |
| `install-prerequisites` | `S install-prerequisites.sh` | Install required dependencies (bun, jq, etc.). |
| `configure-pi` | `S configure-pi.sh` | (Re-)configure Pi extensions, skills, and tsconfig.json. **Run after Pi updates** if `check-pi-extension-types` starts failing. |
| `setup-<client>` | `S setup-{claude-code,cline,copilot,cursor,gemini-cli,hermes,opencode,windsurf,copilot-cli}.sh` | Per-client connectors. Each writes a pointer block into the client's config file. |
| `validate-install` | `S validate-install.sh` | Headless install + idempotent update + doctor in a throwaway sandbox. Catches install-time regressions that the dev doctor misses (live-only bugs). |

## Note + content management

| Tool | Path | What it does |
|---|---|---|
| `validate-note-id` | `S validate-note-id.sh <path>` | Verify a note's `id` matches `uuid5-gen.sh` for its path. Empty output = pass. |
| `ensure-daily-note` | `S ensure-daily-note.sh` | Create today's daily note from `templates/daily.md` (renders `{{date}}` + `{{uuid5}}`). Idempotent. Called by `loop-tick.sh`. |
| `update-daily-note` | `S update-daily-note.sh` | Append session info to today's daily note. |
| `update-startup-context` | `S update-startup-context.sh` | Regenerate `local/sessions/startup-context.md` (live open findings + alerts). Called by `loop-tick.sh`. |
| `loop-tick` | `S loop-tick.sh` | Autonomous tick: doctor + capture-findings + update-startup-context + ensure-daily-note. Run by launchd (`dev.agentbrain.loop`). |
| `capture-findings` | `S capture-findings.sh` | Serialize doctor warnings/errors to `local/findings/<detector>.json` for MCP brain_findings_list. |

## Release / deploy

| Tool | Path | What it does |
|---|---|---|
| `deploy-dev-to-live` | `S deploy-dev-to-live.sh` | Rsync dev framework → live, preserving `local/`, `.git/`, `brain.json`. Validates dev doctor first, then live doctor + validate-install after. Use `--dry-run` to preview. |
| `bump-version` | `S bump-version.sh` | Bump the dev VERSION file (semver). |
| `release` | `S release.sh` | Cut a release tag + push. |
| `publish-gitea-release` / `publish-agentbrain-github` | `S` | Push the release to gitea / github mirror. |
| `release-check` / `dev-sync-status` | `S` | Pre-release sanity + dev/live drift check. |

## Add-on management

| Tool | Path | What it does |
|---|---|---|
| `addons.sh` | `S addons.sh` | Add-on registry CLI: `status`, `check`, install/enable/disable per addon. See [`system/addons/README.md`](addons/README.md). |

## Maintenance / migrations

| Tool | Path | What it does |
|---|---|---|
| `move-agentbrain` | `S move-agentbrain.sh` | Relocate the agentBrain checkout to a new path. |
| `offboard` / `import-offboard` | `S` | Export user content for portability / re-import. |
| `sync-agentbrain-local` | `S sync-agentbrain-local.sh` | Sync `local/` between machines (or to backup). |
| `privacy-scan` | `S privacy-scan.sh` | Scan public files for accidentally-leaked private content (run before any `system/` push). |
| `uninstall` | `S uninstall.sh` | Remove agentBrain connectors from agent configs (does not delete vault). |

## Quality checks (run via `doctor`, but standalone-capable)

Each lives in `scripts/check-*.sh` and is invoked by `doctor.sh`. Standalone-runnable when investigating a specific failure:

- **Schema**: `check-frontmatter`, `check-readmes`, `check-links`, `check-local-content`, `check-session-schema`, `check-spec-version`
- **Architecture**: `check-architecture`, `check-learnings-structure`, `check-path-naming`, `check-rules-pointer-sync`, `check-agentbrain-local`
- **Extensions / addons**: `check-addons`, `check-pi-lens`, `check-pi-extension-types`, `check-events`, `check-launchd-templates`
- **Bootstrap / config**: `check-version`, `check-node-bootstrap`, `check-client-pointers`, `check-lifecycle-scripts`, `check-preference-scopes`, `check-doctor`, `check-skill-tests`
- **Knowledge**: `check-brain-review`

Test scripts (`scripts/test-*.sh`) verify individual subsystems: `test-addons`, `test-doctor`, `test-loop-tick`, `test-new-note`, `test-pi-extensions`, `test-session-continuity`, `test-validate-note-id`.

## Hooks (called by external triggers, not user-invoked)

- `claude-code-validate-note-id-hook.sh` — PostToolUse hook for Claude Code (validates ids written via Write/Edit).
- `setup-launchd-loop.sh` — installs the launchd job for `loop-tick`.
- `setup-git-hooks.sh` — installs git pre-commit hooks.

## Where this file lives in the context tiers

This file is **hot** — read at session start, alongside `rules.md`, `skills.md`, `lifecycle.md`. It is intentionally an *index*, not a manual; full usage per tool is `--help` or the script header.

Token budget: ~600 tokens. Adding a new tool: one row in the right category. If the table grows past 1500 tokens, demote less-common tools to warm tier (or to per-category sub-docs).

## Related

- [`skills.md`](skills.md) — `/command` skills (different concept; this file is for bash tools)
- [`rules.md`](rules.md) — canonical write-location + public/private policy
- [`lifecycle.md`](lifecycle.md) — release / deploy / sync lifecycle stages
- [`addons/README.md`](addons/README.md) — addon system overview
