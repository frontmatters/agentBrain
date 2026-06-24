# agentBrain v1.6.0
> Version: v1.6.0 (2026-06-24)

> **Portable, local-first memory for AI coding agents.** One plain-Markdown knowledge base that Claude Code, Copilot, Pi, Cursor & co. all read from — so your context survives across every session and project.

**This is** the canonical `frontmatters/agentBrain`. **This is not** any of the other similarly-named "agentBrain / Agent Brain" projects.

---

## Why

AI coding agents forget. Claude Code resets each session; Copilot's memory expires after ~28 days; a fresh Cursor or Windsurf chat starts from zero. So you re-explain your stack, your conventions, and the decisions you already made — every single time. The context lives *inside* the agent, and the agent is ephemeral.

agentBrain flips that around. Your knowledge lives in **one Markdown brain on your own disk**, and every agent reads from it. Switch agents, switch projects, start a new session — the brain is still there.

## What it is

- **One brain, many agents.** A single install that every agent in every project points at — not a plugin for one tool, but a shared memory layer underneath all of them.
- **Plain Markdown, local-first.** Your knowledge is human-readable files under your control. It works offline and makes no network calls of its own.
- **Two layers.** A **public framework** (`system/`) defines *how and where* knowledge is organised — rules, skills, templates, guardrails. A **private layer** (`local/`, gitignored) holds *what you actually learned* — patterns, troubleshooting fixes, project notes, preferences.
- **Self-improving.** Agents don't just read the brain; they write back to it — capturing learnings, decisions, and fixes as they work, so it sharpens over time.
- **Yours to remove.** A symmetric `uninstall.sh` reverses exactly what setup added and leaves your data intact.

agentBrain is **not a harness or an agent** — it's the memory layer. The harness (Claude Code, Pi, Copilot, …) chooses to read it.

## How it works

Setup installs a small **pointer** into each agent's global config (`~/.claude/CLAUDE.md`, the Copilot instructions file, Pi's config, …). From then on, every agent — in every project — reads from the same brain:

```
                 ┌──────────────┐
                 │  agentBrain  │   one Markdown knowledge base
                 │ system/+local│   (public framework + your private layer)
                 └──────┬───────┘
        ┌───────────┬───┴───────┬───────────┐
        ▼           ▼           ▼           ▼
   Claude Code   Copilot     Pi / CLI    Cursor …      ← each reads via a pointer + shared skills
```

On top of the pointer, agentBrain ships **skills** — shared slash-commands like `/save-learning`, `/onboard`, `/project-update` — symlinked into each agent's native skills dir, and opt-in **add-ons** that extend it (YouTube ingestion, design critique, an event bus, and more). Every add-on declares a privacy level you confirm before enabling.

## Quick Start

**Which entry point?** macOS + full [Pi](https://github.com/parahelp/pi) integration → `bootstrap-macos.sh`. Any other platform, or a minimal install for Claude Code / Copilot / Cursor / etc. → `setup.sh`. Both are idempotent — safe to re-run.

**macOS with Pi** (recommended):

```bash
git clone https://github.com/frontmatters/agentBrain.git ~/Developer/agentBrain
cd ~/Developer/agentBrain
bash scripts/bootstrap-macos.sh
```

Installs developer tools (Node, bun), the agentBrain structure + agent pointers, Pi extensions/skills/config, and runs health checks.

**Other platforms or a minimal setup:**

```bash
git clone https://github.com/frontmatters/agentBrain.git ~/Developer/agentBrain
cd ~/Developer/agentBrain
./setup.sh
```

Prefer to read before you run? Clone first, then inspect `setup.sh` — it's plain, idempotent, and makes no hidden network calls (see [What it writes & network behavior](#what-it-writes--network-behavior) below). To remove everything later: `bash scripts/uninstall.sh`.

## What it writes & network behavior

Transparency first — exactly what agentBrain touches on your machine:

- **Writes:** your private vault (`local/`, default `~/.agentBrain/`); per-agent skills
  directories as symlinks into the brain (e.g. `~/.claude/skills/`, `~/.pi/agent/skills/`);
  and — only if you opt in during `/onboard` — one `export AGENTBRAIN_LOCALE=…` line in
  your shell rc.
- **Network:** day-to-day the core reads/writes local Markdown and makes **no network calls
  of its own**. Setup and `bootstrap-macos.sh` do fetch dependencies (the `git clone`, and on
  macOS Node/bun via Homebrew) — visible in the scripts. Add-ons are opt-in and each declares a
  `privacy:` level (`local` / `sends-docs` / `sends-all`) shown and confirmed before it is
  enabled — nothing leaves your machine unless you turn on an add-on that says so.
- **Credentials:** the core never reads or stores secrets; that is confined to opt-in
  add-ons (e.g. `secrets-helper`). See [SECURITY.md](./SECURITY.md).
- **Removal:** `scripts/uninstall.sh` reverses what setup added and leaves your vault/data intact.

## Structure

| Folder                            | Purpose                                                                 |
| --------------------------------- | ----------------------------------------------------------------------- |
| `.github/copilot-instructions.md` | Copilot entry point — read automatically                                |
| `.github/skills/`                 | Slash commands for GitHub Copilot (native format)                       |
| `CLAUDE.md`                       | Claude Code entry point                                                 |
| `learnings/`                      | Public placeholders/examples only; real learnings → `local/learnings/`  |
| `user-preferences/`               | Public templates only; real preferences → `local/preferences/personal/` |
| `templates/`                      | Templates for notes, projects, and local starter files                  |
| `system/`                         | Rules, skills, agent configs, Pi config, integrations                   |
| `system/agent-config/`            | Per-agent instructions (pi.md, claude.md, copilot.md, …)                |
| `system/pi-config/`               | Pi extensions, skills, bootstrap, Brewfile                              |
| `system/integrations/`            | Public integration docs (opensrc, …)                                    |
| `scripts/`                        | Helper scripts (setup, privacy-scan, sync, publish)                     |
| `local/`                          | **Private** — gitignored, never pushed (see below)                      |

### local/ — private layer

Created automatically by `scripts/bootstrap-macos.sh` on every machine:

```
local/
├── projects/           ← your project notes (one subfolder per project)
├── learnings/          ← real patterns, troubleshooting, discoveries
│   └── extracted/      ← auto-extracted by Pi extract-learnings extension
├── preferences/        ← scoped preferences: personal/ always, organization/ and team/ optional
├── integrations/       ← tool configs, API key references (no token values)
├── security/           ← auth setup notes, keychain guides
├── memories/           ← personal agent context
├── research/           ← research notes
├── reports/            ← generated reports and analysis outputs
├── sessions/           ← session logs
├── daily-notes/        ← daily notes (auto-created by ensure-daily-note.sh)
├── setup-history/      ← machine setup history
├── youtube-knowledge/  ← downloaded transcripts (Pi youtube extension)
└── backlog/            ← personal backlog
```

Preference scopes:

```
local/preferences/
├── personal/       ← your individual language, stack, workflow, style (always)
├── organization/   ← optional broader organization context/rules
└── team/           ← optional team-specific agreements
```

Agents read all scopes that exist. Scopes are additive context; if scopes appear to disagree, agents should surface the tension instead of inventing hidden precedence rules.

### Project notes convention

```
local/projects/[name]/
  index.md        (required)
  prd.md          (optional — requirements, user stories)
  decisions.md    (optional — architecture decisions)
  deploy.md       (optional — deploy config)
  changelog.md    (optional — change log)
  context.md      (optional — what to read per phase)
```

## Agent Compatibility

| Agent               | Setup                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Pi**              | `scripts/bootstrap-macos.sh` — installs Pi, symlinks extensions + skills, generates tsconfig                    |
| **Claude Code**     | `scripts/setup.sh` — adds pointer to `~/.claude/CLAUDE.md`                                                      |
| **VS Code Copilot** | Manual — add `.github/copilot-instructions.md` in VS Code settings; see `system/agent-config/vscode-copilot.md` |
| **GitHub Copilot CLI** | `scripts/setup.sh` — writes a pointer to `~/.copilot/copilot-instructions.md`                                  |
| **Windsurf**        | `scripts/setup.sh` — adds pointer to `global_rules.md`                                                          |
| **OpenCode**        | `scripts/setup.sh` — adds instructions to `~/.config/opencode/opencode.json`                                    |
| **Gemini CLI**      | `scripts/setup.sh` — adds pointer to `~/.gemini/GEMINI.md`                                                      |
| **Cline**           | `scripts/setup.sh` — creates `~/Documents/Cline/Rules/agentBrain.md`                                            |
| **Cursor**          | Manual — paste pointer in Settings > Rules; see `system/agent-config/cursor.md`                                 |
| **Obsidian**        | Open checkout as vault — graph view, backlinks, search                                                          |

See `system/agent-config/` for per-agent details.

## Pi Setup (bootstrap)

`scripts/bootstrap-macos.sh` does the full macOS setup in one command:

Bootstrap orchestrates four steps:

| Step              | Script                             | What                                                 |
| ----------------- | ---------------------------------- | ---------------------------------------------------- |
| 1 — Prerequisites | `scripts/install-prerequisites.sh` | nvm, Node LTS, Homebrew tools, Pi, opensrc           |
| 2 — agentBrain    | `scripts/setup.sh`                 | `local/` structure, agent pointers for all clients   |
| 3 — Pi config     | `scripts/configure-pi.sh`          | Extensions, skills, tsconfig, API check, credentials |
| 4 — Validation    | `scripts/doctor.sh`                | Full health audit                                    |

**Idempotent** — safe to re-run after a Pi update or on a new machine.

## Skills

| Skill                 | What it does                                                                             |
| --------------------- | ---------------------------------------------------------------------------------------- |
| `/save-learning`      | Save a real insight to `local/learnings/`                                                |
| `/save-troubleshoot`  | Log a problem + solution                                                                 |
| `/project-update`     | Create or update a project note in `local/projects/`                                     |
| `/doctor`             | Health audit for the agentBrain framework (`--pi-lens-strict` for release-quality gates) |
| `/brain-review`       | Audit the brain for quality and staleness                                                |
| `/brain-insights`     | Surface work patterns from recent sessions                                               |
| `/onboard`            | Interactive setup to personalize preference scopes                                       |
| `/capture-tool-info`  | Capture tool/auth/service info into `local/`                                             |
| `/refactor-brain`     | Plan + execute safe brain refactors                                                      |
| `/opensrc`            | Fetch dependency source code for deeper agent context                                    |
| `/lightpanda`         | Headless-browser web search/scrape                                                       |
| `/understand`         | Knowledge graph of the agentBrain codebase                                               |
| `/understand-project` | Knowledge graph of an external project                                                   |
| `/journal`            | Inspect or update the session-journal (`show` / `save` / `task` / `archive` / `config`)  |
| `/selftest`           | Verify Claude Code integration (session-journal + memory-redirect, hooks, UUID5)         |
| `/add-locale`         | Add a new UI language to `scripts/lib/_strings.sh` interactively                         |

`system/skills.md` is the canonical index (it carries the per-skill `SKILL.md` paths).

Skills live in the agnostic home `system/skills/`; every client links into it:

- **Pi**: via `~/.pi/agent/skills/` (symlinked from `system/skills/` by `configure-pi.sh`; Pi-specific skills come from `system/pi-config/skills/`)
- **GitHub Copilot**: native slash commands via `.github/skills/` (symlinks into `system/skills/`)
- **All other agents**: via `system/skills.md`, read at session start

## Pi Extensions

Custom Pi extensions in `system/pi-config/extensions/`, symlinked to `~/.pi/agent/extensions/`:

| Extension               | What it does                               |
| ----------------------- | ------------------------------------------ |
| `agentbrain.ts`         | Injects project context into every session |
| `session-continuity.ts` | Archives/starts the session journal in Pi  |
| `extract-learnings.ts`  | Auto-extracts learnings before compaction  |
| `youtube-transcript.ts` | Download + save YouTube transcripts        |
| `pi-cloak/index.ts`     | Redacts secrets from tool output           |
| `glm.ts`                | GLM / z.ai provider                        |
| `ollama-cloud.ts`       | Ollama Cloud provider                      |
| `flow-title.ts`         | Animated gradient session header           |
| `tps-tracker.ts`        | Live tokens/s display                      |
| `git-status-widget.ts`  | Git status in sidebar                      |

See `system/pi-config/extensions/extensions.md` for API compatibility details.

## Integrations

| Integration | Docs                                                                  |
| ----------- | --------------------------------------------------------------------- |
| `opensrc`   | `system/integrations/opensrc.md` — fetch dependency source for agents |
| Gitea       | `local/integrations/gitea.md` (private)                               |

## Add-ons

Opt-in, agent-agnostic tools under `system/addons/`. Manage via `scripts/addons.sh` (`status`/`install`/`enable`/`disable`/`check`/`test`); test a single add-on with `bash scripts/addons.sh test <id>`. Never a core dependency; doctor never fails on a missing add-on. See `system/addons/README.md`.

| Add-on                   | What it does                                                                            |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `session-journal`        | Auto-fills `local/sessions/session-journal.md` via Stop + PostToolUse hooks; `/journal` slash command |
| `claude-memory-redirect` | Routes Claude Code's project-memory dir to `local/memories/projects/<slug>/` via symlink (or sync-hook / instruction-only) |
| `graphify`               | Builds a knowledge graph view of the vault                                              |
| `voice`                  | Voice capture flows                                                                     |
| `weekly-review`          | Scheduled weekly retrospective                                                          |
| `youtube-knowledge`      | Sync YouTube channel transcripts (CLI + scheduled job)                                  |
| `event-bus`              | Async cross-agent event-bus (used by `/peer-review`)                                    |

### Verifying the integration (`scripts/selftest.sh`)

Agent-agnostic dispatcher — runs the generic framework checks (always) plus a section per detected agent (Claude Code, Pi, Copilot CLI, Gemini CLI). Agents that are not installed are explicitly skipped, not silently ignored.

```bash
bash scripts/selftest.sh                       # everything
bash scripts/selftest.sh --list                # show available agent modules
bash scripts/selftest.sh --only=claude-code    # one agent (comma-separated for multiple)
```

Or `/selftest` inside Claude Code. The legacy `scripts/selftest-claude-integration.sh` still works but is deprecated — it forwards to `selftest.sh --only=claude-code`. Non-destructive (one write/delete cycle in the Claude memory-redirect end-to-end test). Locale-aware (`$LANG` or `AGENTBRAIN_LOCALE`). To add a new agent module, see `scripts/selftest/README.md`.

## Locale

User-facing scripts (install scripts, selftest, doctor output) are localised via `scripts/lib/_strings.sh`. Supported: **`nl`** and **`en`**. Resolution order:

1. `AGENTBRAIN_LOCALE` environment variable (explicit override — `nl` or `en`)
2. `$LANG` (first 2 chars — `nl_NL.UTF-8` → `nl`, `en_US.UTF-8` → `en`)
3. Fallback: `en`

Unsupported locales (e.g. `de`, `fr`) fall back to English. To add a third language, run `/add-locale` (or edit `_strings.sh` manually — add a `_t_xx()` function and extend the dispatcher in `t()`).

```bash
AGENTBRAIN_LOCALE=en bash scripts/selftest.sh   # force English on a Dutch machine
```

The locale is resolved once per script and exported as `_AGENTBRAIN_LOCALE` (private/internal name, prefix `_` marks it as set by the helper rather than the user), so child processes inherit it.

## Self-Learning Protocol

| Trigger                | Destination                      |
| ---------------------- | -------------------------------- |
| Framework/rule change  | `system/`                        |
| Template change        | `templates/`                     |
| Real technical insight | `local/learnings/`               |
| Project milestone      | `local/projects/[name]/index.md` |

See `system/rules.md` for the full protocol.

## Public vs Private

**Public = HOW/WHERE. Private = WHAT.**

```
~/Developer/agentBrain/
├── system/             ← shared framework (rules, agent configs, Pi config)
├── learnings/          ← public placeholders/examples only
├── templates/          ← shared templates + local starter files
├── user-preferences/   ← public examples/templates only
├── scripts/            ← helper scripts
└── local/              ← PERSONAL (gitignored, never pushed)
    ├── projects/       ← your project notes
    ├── learnings/      ← real discoveries and troubleshooting
    ├── preferences/    ← scoped preferences (personal/, optional organization/team)
    ├── integrations/   ← tool configs (no token values)
    └── …
```

`git pull` updates the framework without touching `local/`.

## Obsidian Vault

agentBrain is an Obsidian vault. `.obsidian/` config is tracked in git (minimal); cache and workspace files are gitignored.

- Wiki-links (`[[note-name]]`) in Related sections
- Graph view shows connections between notes
- UUID5 IDs in frontmatter — generate with `scripts/uuid5-gen.sh "path/to/note"`

## Lifecycle

agentBrain has a complete lifecycle from installation to removal:

```
SETUP → ONBOARD → BOOTSTRAP (Pi) → POSTINSTALL → DAILY USE
  ↓                                                ↓
MOVE ←                              OFFBOARD → IMPORT
  ↓
UNINSTALL
```

### Setup — `./setup.sh`

First‑time installation for all agents. Idempotent (safe to re‑run).

```bash
cd ~/Developer/agentBrain && ./setup.sh
```

Modular orchestrator — each step is a subscript that also runs standalone. Creates the `local/` structure, **optionally offers to install agent CLIs you don't have yet** (opt-in, agnostic — never auto-installs; `scripts/install-agent-clis.sh`), writes a pointer (connector) + skills + behaviors for each detected AI tool — Claude Code, Gemini CLI, Copilot CLI, Cline, OpenCode, Windsurf (VS Code Copilot and Cursor print manual steps) — ensures a daily note exists, and validates.

Flags (`./setup.sh --help` for all): `--yes` (non-interactive), `--home=PATH` (advanced — install base for tool configs, default `$HOME`; for sandbox/CI/alternate profiles), `--move-to PATH` (relocate the checkout). `AGENTBRAIN_HOME` and `AGENTBRAIN_SKIP_PI=1` are the env equivalents.

### Onboarding — `/onboard`

Personalize preference scopes. `/onboard` starts with `local/preferences/personal/`, then optionally captures organization and team context. Works in Pi, Claude, Copilot, and Windsurf.

### Bootstrap — `scripts/bootstrap-macos.sh`

Full macOS setup: developer tools + agentBrain + Pi. Orchestrates `install-prerequisites.sh` → `setup.sh` → `configure-pi.sh` → `doctor.sh`. macOS only. Includes everything `./setup.sh` does.

### Postinstall — `system/pi-config/bin/pi`

The Pi wrapper automatically applies compatibility patches after updates when enabled.

### Move — `scripts/move-agentbrain.sh` or `scripts/setup.sh --move-to`

Safely move agentBrain to a new location. Updates all pointers, symlinks, env vars, and absolute paths. Creates a backup first.

```bash
scripts/setup.sh --move-to /Volumes/SSD2/agentBrain
```

### Offboard — `scripts/offboard.sh`

Export knowledge and personal preferences for transfer to another machine. Includes `local/preferences/personal/`, projects, learnings, daily notes, sessions, reports. Runs privacy scan on export. Team preferences are included only with `--include-team`.

```bash
scripts/offboard.sh                         # last 90 days of daily notes
scripts/offboard.sh --all                   # all daily notes
scripts/offboard.sh --all --include-team    # include local team scope too
```

### Import — `scripts/import-offboard.sh`

Import an offboard export. Never overwrites existing files.

```bash
scripts/import-offboard.sh ~/agentBrain-export-20260520-120000.tar.gz
```

### Uninstall — `scripts/uninstall.sh`

Remove all agent pointers, Pi symlinks, env vars. The checkout is preserved by default. Suggests running offboard first if local files exist.

```bash
scripts/uninstall.sh
```

### Daily note — `scripts/ensure-daily-note.sh`

Ensures a daily note exists for today. Called automatically by setup.sh. Agent‑agnostic.

## Scripts

| Script                                 | Usage                                                            |
| -------------------------------------- | ---------------------------------------------------------------- |
| `./setup.sh`                           | Install agent pointers for all clients (`--move-to` to relocate) |
| `scripts/install-prerequisites.sh`     | Install developer tools: nvm, Node LTS, Homebrew, bun, uv        |
| `scripts/setup-agent-integrations.sh`  | Install agentBrain pointers for all detected AI clients (per-client `setup-<client>.sh`) |
| `scripts/configure-pi.sh`              | Install + configure Pi: extensions, skills, tsconfig             |
| `scripts/bootstrap-macos.sh`           | Full macOS bootstrap: dev tools + agentBrain + Pi (orchestrator) |
| `scripts/doctor.sh`                    | Run the full agentBrain health audit                             |
| `scripts/offboard.sh`                  | Export knowledge + preferences (`--all` for everything)          |
| `scripts/import-offboard.sh`           | Import an offboard export                                        |
| `scripts/uninstall.sh`                 | Remove pointers, symlinks, env vars                              |
| `scripts/move-agentbrain.sh`           | Safely move to a new location                                    |
| `scripts/ensure-daily-note.sh`         | Guarantee today's daily note exists                              |
| `scripts/privacy-scan.sh`              | Check public repo for accidental private content                 |
| `scripts/check-readmes.sh`             | Check README coverage                                            |
| `scripts/check-frontmatter.sh`         | Check public markdown frontmatter/schema hygiene                 |
| `scripts/check-session-schema.sh`      | Check session continuity naming/schema rules                     |
| `scripts/check-preference-scopes.sh`   | Check scoped preference contract                                 |
| `scripts/check-node-bootstrap.sh`      | Check nvm-managed Node bootstrap contract                        |
| `scripts/check-lifecycle-scripts.sh`   | Check setup/offboard/import/uninstall/move contracts             |
| `scripts/check-client-pointers.sh`     | Check cross-client pointer consistency                           |
| `scripts/check-pi-lens.sh`             | Check unresolved local Pi-lens worklog findings                  |
| `scripts/check-links.sh`               | Check public wiki-link targets                                   |
| `scripts/check-path-naming.sh`         | Report path naming drift                                         |
| `scripts/check-brain-review.sh`        | Semantic quality: stale, duplicate, misclassified                |
| `scripts/sync-agentbrain-local.sh`     | Commit + push private `local/` to its own repo                   |
| `scripts/test-session-continuity.sh`   | Test session archive naming, collision, chain                    |
| `scripts/publish-agentbrain-github.sh` | Push public repo to GitHub after Gitea review                    |
| `scripts/uuid5-gen.sh`                 | Generate deterministic UUID5 for note frontmatter                |
| `scripts/update-daily-note.sh`         | Add entry to today's daily note                                  |

## Release workflow commands

New helper scripts added to streamline dev‑first workflow:

| Command                         | Description                                                                                                                                                             |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/dev-sync-status.sh`    | Shows live/dev sync status, optional `--doctor` for full diagnostics                                                                                                    |
| `scripts/deploy-dev-to-live.sh` | Safely rsync public layer from `agentBrain-dev` → `agentBrain` (dry‑run by default). Use `--apply` to perform the sync and `--pi-smoke` to validate Pi after deployment |
| `scripts/release-check.sh`      | End‑to‑end release validation: doctor, privacy scan, zip build, private‑path check, disposable test‑install, final doctor                                               |
|                                 |

## License

Apache License 2.0 — see [`LICENSE`](./LICENSE).
