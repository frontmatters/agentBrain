# agentBrain

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
- **Sealed spaces for client work.** Confidential employer/client knowledge lives in per-owner compartments (`local/spaces/<slug>/`) that stay out of your personal sync and out of default recall — with a boundary guard that fails the build on leaks.
- **Yours to remove.** A symmetric `uninstall.sh` reverses exactly what setup added and leaves your data intact.

agentBrain is **not a harness or an agent** — it's the memory layer. The harness (Claude Code, Pi, Copilot, …) chooses to read it. And it is deliberately **not** a RAG stack: no database, no embeddings, no cloud account — just files, git, and conventions that agents follow.

Under the hood that adds up to real surface: ~40 shared skills, 23 opt-in add-ons, integrations for 11 agents/editors, and a doctor with 50+ checks guarding both the framework and your knowledge.

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

## What you can do with it

### Capture knowledge as you work

Fixed a gnarly build issue? `/save-troubleshoot`. Discovered how a vendor API
really behaves? `/save-learning`. Project reached a milestone? `/project-update`.
Notes get typed frontmatter, stable UUID5 identity, and wiki-links — and your
preferences live in three additive scopes (`personal/`, optional
`organization/` and `team/`) that every agent reads. `/grill-me` runs a
structured interview that pulls tacit knowledge out of your head and into the
vault.

### Never lose your thread

The `session-journal` add-on keeps a rolling journal of what each session did;
`/park` checkpoints work-in-progress (status, insights, a ready-to-paste resume
prompt) and `/unpark` picks it up in a fresh session — days later, in a
different agent. Daily notes accumulate automatically, `weekly-review` can
summarize your week on a schedule, and the `still-needed` add-on answers "is
this still open, or did another session already fix it?" before you act on
stale work. For Claude Code, `claude-memory-redirect` routes its per-project
memory into the brain so even that survives.

### Keep client work sealed

Spaces (below) compartmentalize employer/client knowledge with a doctor-enforced
boundary guard. `/incognito` gives you a read-only session — consult everything,
write nothing. The `pi-cloak` extension redacts secrets from tool output,
`secrets-helper` fetches credentials from the macOS keychain so they never live
in files, `git-email-guard` blocks commits from the wrong identity, and a
privacy scan gates every public commit and every release archive.

### A brain that stays healthy

Knowledge rots; agentBrain treats that as an engineering problem. `/doctor`
audits 50+ aspects — including whether the docs still tell the truth (the
skills index, the architecture inventory, and the canonical reading list are
all parity-checked). `/brain-review` finds stale and duplicate notes,
`wash-vault` normalizes dirty frontmatter, and the forget-lifecycle is
recoverable by design: `/brain-forget` soft-deletes into a trash,
`/brain-recall` restores, `/brain-purge` makes it final — never silently.
Whole projects move in and out of the vault as portable packages
(`/brain-extract` / `/brain-restore`), and a `shared/` layer syncs selected
knowledge across machines or a team (see `docs/shared-vault.md`).

### Agents that talk to each other

The `agentbrain-mcp` add-on exposes the brain as an MCP server
(`brain_search`, `brain_recent`, `brain_read`, `brain_save_learning`, …) for
any MCP-capable agent. The `event-bus` add-on gives agents filesystem pub/sub:
`/peer-review` uses it to hand a document to *another* model for an independent
verdict while you keep working. `shorthand` teaches every agent your personal
abbreviations — define `ab` → agentBrain once, and every agent understands it.

### Feed it, and look inside it

`youtube-digest` syncs channel transcripts into searchable notes on a schedule;
`/opensrc` pulls dependency source code so agents read how a library actually
works; `/understand` and `graphify` build interactive knowledge graphs of a
codebase or the vault itself; `brain-explain` renders any note as a themed,
self-contained HTML explainer. And because the checkout is a valid Obsidian
vault, graph view, backlinks and full-text search work out of the box.

### Update without fear

Three release channels (`edge` / `prerelease` / `stable`); `brain-update`
records the exact ref before touching anything, gates every update on the
doctor, and can roll back. `selftest` verifies the integration per detected
agent, and `uninstall.sh` is symmetric: it removes exactly what setup added and
proves your data untouched.

## Quick Start

The fastest route is the installer (clones this repo and runs its setup; safe to re-run):

```bash
curl -fsSL https://getagentbrain.com/install.sh | bash
```

Prefer explicit steps, or want the full [Pi](https://github.com/earendil-works/pi) integration on macOS? Pick an entry point — both are idempotent:

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

- **Writes:** your private vault (`local/` — by default a real directory inside the
  checkout; an existing `~/.agentBrain/vault` is symlinked instead when present, or pass
  `--vault` to choose a location); per-agent skills
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
| `projects/`                       | Public example + registry (`projects/_example/`); real projects → `local/projects/` |
| `sessions/`                       | Public placeholder; real session logs → `local/sessions/`               |
| `daily-notes/`                    | Public placeholder; real daily notes → `local/daily-notes/`             |
| `backlog/`                        | Public placeholder; real backlog → `local/backlog/`                     |
| `youtube-digest/`                 | Public placeholder; real transcripts → `local/youtube-digest/`          |
| `user-preferences/`               | Public templates only; real preferences → `local/preferences/personal/` |
| `templates/`                      | Templates for notes, projects, and local starter files                  |
| `docs/`                           | Public documentation (e.g. the `shared/` knowledge layer)               |
| `tests/`                          | Framework test suites/fixtures                                          |
| `system/`                         | Rules, skills, agent configs, Pi config, integrations                   |
| `system/agent-config/`            | Per-agent instructions (pi.md, claude.md, copilot.md, …)                |
| `system/pi-config/`               | Pi extensions, skills, bootstrap, Brewfile                              |
| `system/integrations/`            | Public integration docs (opensrc, …)                                    |
| `scripts/`                        | Helper scripts (setup, privacy-scan, sync, publish)                     |
| `local/`                          | **Private** — gitignored, never pushed (see below)                      |

### local/ — private layer

Created automatically by `setup.sh` (via `scripts/setup-structure.sh`) on every machine;
`scripts/bootstrap-macos.sh` is the macOS wrapper that runs it:

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
├── youtube-digest/     ← downloaded transcripts (youtube-digest add-on)
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

### Spaces — sealed compartments for client work

When you work for multiple clients or an employer, some knowledge must never mix
with your personal brain. A *space* is a sealed compartment under
`local/spaces/<slug>/` with its own passport (`owner`, a stable `space-id`,
optional sync remote):

- Excluded from the personal vault sync and from default recall
  (`brain_search`/`brain_recent` skip spaces unless asked).
- Write into one with `new-note.sh --space <slug>` (or set it active);
  view with `list-learnings` / `list-projects --space <slug>`.
- Deliver a whole space as a stamped, portable package with
  `brain-extract --space <slug>`, re-import with `brain-restore`.
- A boundary guard in the doctor fails the build if sealed content is staged
  for the personal sync or if a space's identifiers leak into public files.

## Agent Compatibility

| Agent               | Setup                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Pi**              | `scripts/bootstrap-macos.sh` — installs Pi, symlinks extensions + skills, generates tsconfig                    |
| **Claude Code**     | `scripts/setup.sh` — adds pointer to `~/.claude/CLAUDE.md`                                                      |
| **VS Code Copilot** | Manual — add `.github/copilot-instructions.md` in VS Code settings; see `system/agent-config/vscode-copilot.md` |
| **GitHub Copilot CLI** | `scripts/setup.sh` — writes a pointer to `~/.copilot/copilot-instructions.md`                                  |
| **Windsurf**        | `scripts/setup.sh` — adds pointer to `global_rules.md`                                                          |
| **OpenCode**        | `scripts/setup.sh` — writes `~/.config/opencode/agentbrain-pointer.md` and registers it in the `instructions` array of `~/.config/opencode/opencode.json` |
| **Gemini CLI**      | `scripts/setup.sh` — adds pointer to `~/.gemini/GEMINI.md`                                                      |
| **Cline**           | `scripts/setup.sh` — creates `~/Documents/Cline/Rules/agentBrain.md`                                            |
| **Cursor**          | Manual — paste pointer in Settings > Rules; see `system/agent-config/cursor.md`                                 |
| **Hermes**          | `scripts/setup.sh` — pointer block in `~/.hermes/SOUL.md`                                                        |
| **Obsidian**        | Open checkout as vault — graph view, backlinks, search                                                          |

See `system/agent-config/` for per-agent details.

## Pi Setup (bootstrap)

`scripts/bootstrap-macos.sh` does the full macOS setup in one command:

Bootstrap orchestrates four steps:

| Step              | Script                             | What                                                 |
| ----------------- | ---------------------------------- | ---------------------------------------------------- |
| 1 — Prerequisites | `scripts/install-prerequisites.sh` | nvm-managed Node (LTS via nvm, never Homebrew Node), Homebrew tools, Pi, opensrc |
| 2 — agentBrain    | `scripts/setup.sh`                 | `local/` structure, agent pointers for all clients   |
| 3 — Pi config     | `scripts/configure-pi.sh`          | Extensions, skills, tsconfig, API check, credentials |
| 4 — Validation    | `scripts/doctor.sh`                | Full health audit                                    |

**Idempotent** — safe to re-run after a Pi update or on a new machine.

## Skills

Shared slash-commands, written once and linked into every agent's native skills
directory. A few everyday ones:

| Skill                | What it does                                                    |
| -------------------- | ---------------------------------------------------------------- |
| `/onboard`           | Personalize preferences, add-ons, locale, and release channel    |
| `/save-learning`     | Capture a real insight into `local/learnings/`                   |
| `/save-troubleshoot` | Log a problem + its solution                                     |
| `/project-update`    | Create or update a project note                                  |
| `/park` + `/unpark`  | Checkpoint work-in-progress and resume it reliably later         |
| `/doctor`            | Full health audit of the framework                               |
| `/brain-review`      | Audit the brain for quality and staleness                        |
| `/incognito`         | Read-only session: consult the brain, write nothing              |

The complete, drift-guarded index of all skills lives in
[`system/skills.md`](./system/skills.md) — a doctor check enforces that it
matches the skill directories one-to-one.

Skills live in the agnostic home `system/skills/`; every client links into it:

- **Pi**: via `~/.pi/agent/skills/` (symlinked by `configure-pi.sh`; Pi-specific skills come from `system/pi-config/skills/`)
- **GitHub Copilot**: native slash commands via `.github/skills/` (symlinks into `system/skills/`)
- **All other agents**: via `system/skills.md`, read at session start

## Pi Extensions

For [Pi](https://github.com/earendil-works/pi), agentBrain goes deeper than a
pointer: TypeScript extensions (strict-typed, tested) hook into the session
lifecycle — context injection at session start, automatic learning-extraction
before compaction, session-journal continuity, secret redaction in tool output
(`pi-cloak`), and note-id enforcement. The full inventory with API-compatibility
notes lives in
[`system/pi-config/extensions/extensions.md`](./system/pi-config/extensions/extensions.md).

## Integrations

Public integration docs live under `system/integrations/` (e.g. `opensrc` —
fetch dependency source code so agents can read how a library really works).
Your own tool and service notes go in the private layer, where agents find
them before ever asking you for credentials.

## Add-ons

Opt-in, agent-agnostic tools under `system/addons/`. Manage via `scripts/addons.sh` (`status`/`install`/`enable`/`disable`/`check`/`test`); test a single add-on with `bash scripts/addons.sh test <id>`. Never a core dependency; doctor never fails on a missing add-on. See `system/addons/README.md`.

| Add-on                   | What it does                                                                            |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `agent-browser`          | Registry entry for the `vercel-labs/agent-browser` browser-automation CLI              |
| `agentbrain-mcp`         | Direct-file MCP server over the brain for MCP-capable agents                            |
| `anthropic-skills`       | Registry entry for Anthropic's official Claude skills (not vendored)                    |
| `brain-explain`          | Render markdown notes into themed, self-contained HTML explainers                       |
| `claude-memory-redirect` | Routes Claude Code's project-memory dir to `local/memories/projects/<slug>/` via symlink (or sync-hook / instruction-only) |
| `event-bus`              | Filesystem pub/sub for cross-agent communication (used by `/peer-review`)               |
| `extract-learnings`      | Auto-extracts durable learnings from a session before compaction                        |
| `git-email-guard`        | Pre-commit hook that blocks commits from non-whitelisted git emails                     |
| `graphify`               | Builds a knowledge graph view of the vault                                              |
| `headroom-proxy`         | Local proxy that compresses tool output/context to save tokens                          |
| `impeccable`             | Registry entry for the community `impeccable` frontend-design skill                     |
| `incognito`              | Read-only session mode: consult the brain, write nothing                                |
| `routa`                  | Workspace-first multi-agent delivery board                                              |
| `secrets-helper`         | Tiered macOS-keychain secret retrieval                                                  |
| `session-journal`        | Auto-fills `local/sessions/session-journal.md` via Stop + PostToolUse hooks; `/journal` slash command |
| `shorthand`              | Personal abbreviations understood by every agent                                        |
| `sitescope`              | Website/webapp analysis CLI (CDP snapshots, screenshots, interactions)                  |
| `still-needed`           | "Is this still needed?" relevance check across parallel sessions                        |
| `trailofbits-skills`     | Registry entry for Trail of Bits' security skills (not vendored)                        |
| `understand-anything`    | Interactive knowledge graph of a codebase                                               |
| `uxray`                  | UI design critique for web, Tauri, macOS and iOS                                        |
| `weekly-review`          | Weekly vault-activity summary (scheduled)                                               |
| `youtube-digest`         | Sync YouTube channel transcripts into the brain (CLI + scheduled job)                   |

### Verifying the integration (`scripts/selftest.sh`)

Agent-agnostic dispatcher — runs the generic framework checks (always) plus a section per detected agent (Claude Code, Pi, Copilot CLI, Gemini CLI). Agents that are not installed are explicitly skipped, not silently ignored.

```bash
bash scripts/selftest.sh                       # everything
bash scripts/selftest.sh --list                # show available agent modules
bash scripts/selftest.sh --only=claude-code    # one agent (comma-separated for multiple)
```

Or `/selftest` inside Claude Code. The legacy `scripts/selftest-claude-integration.sh` still works but is deprecated — it forwards to `selftest.sh --only=claude-code`. Non-destructive (one write/delete cycle in the Claude memory-redirect end-to-end test). Locale-aware (`$LANG` or `AGENTBRAIN_LOCALE`). To add a new agent module, see `scripts/selftest/README.md`.

## Locale

A small set of user-facing scripts is localised via `scripts/lib/_strings.sh` — currently `selftest.sh`, `check-agnostic.sh`, and two addon installers. Other scripts (`doctor.sh`, `setup.sh`, `addons.sh`) are English-only. Supported: **`nl`** and **`en`**. Resolution order:

1. `AGENTBRAIN_LOCALE` environment variable (explicit override — `nl` or `en`)
2. `$LANG` (first 2 chars — `nl_NL.UTF-8` → `nl`, `en_US.UTF-8` → `en`)
3. Fallback: `en`

Unsupported locales (e.g. `de`, `fr`) fall back to English. To add a third language, run `/add-locale` (or edit `_strings.sh` manually — add a `_t_xx()` function and extend the dispatcher in `t()`).

```bash
AGENTBRAIN_LOCALE=en bash scripts/selftest.sh   # force English on a Dutch machine
```



## Self-Learning Protocol

The brain is not a wiki you maintain by hand. Agents are instructed to write
back what they learn while working: a durable technical insight becomes a note
in `local/learnings/`, a project milestone updates that project's note, and a
framework improvement lands in `system/`. The full protocol — including when
*not* to write — is defined in [`system/rules.md`](./system/rules.md).

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

Personalize the install: preference scopes, addons (essential addons recommended), UI locale, and release channel. `/onboard` starts with `local/preferences/personal/`, then optionally captures organization and team context. As a skill it runs in Claude Code, Copilot CLI, and Pi; pointer-only agents can follow the same steps manually via `system/skills.md`.

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

## Everyday commands

| Command                       | What it does                                                     |
| ----------------------------- | ----------------------------------------------------------------- |
| `bash scripts/doctor.sh`      | Full health audit (framework + your vault)                        |
| `bash scripts/selftest.sh`    | Verify the integration per detected agent                         |
| `bash scripts/addons.sh status` | See, install, enable or disable add-ons                         |
| `bash scripts/brain-update.sh --check` | Check for framework updates on your release channel      |
| `bash scripts/offboard.sh`    | Export knowledge + preferences for another machine                |
| `bash scripts/import-offboard.sh <file>` | Import such an export (never overwrites)               |
| `bash scripts/uninstall.sh`   | Remove pointers, symlinks and env vars; your data stays           |

Every script in `scripts/` is plain, commented bash — the full inventory is in
[`scripts/README.md`](./scripts/README.md). Maintainer topics (dual-checkout
development, quality gates, cutting a release) are documented in
[`docs/development.md`](./docs/development.md).

## License

Apache License 2.0 — see [`LICENSE`](./LICENSE).
