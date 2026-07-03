---
date: 2026-05-18
type: system
tags: [changelog, meta]
id: 2bf62fb7-49d8-53e4-ba98-cb79a7742984
---

# Changelog

All notable changes to agentBrain are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v1.6.1] - 2026-07-03

Consolidates the 1.6.1 prerelease line (01-05, entries below) plus the final
hardening round. Highlights:

### Added

- **Spaces — sealed per-owner compartments** at `local/spaces/<slug>/` for
  employer/client knowledge: excluded from personal sync and default recall,
  written via `new-note.sh --space`, viewed via `list-* --space`, delivered as
  `space-id`-stamped packages (`brain-extract --space` / `brain-restore`), with
  per-space sync remotes, an active-space marker, and a boundary guard in doctor
  that fails the build on seal breaches or confidential leaks — including in
  non-git checkouts (fail-open closed).
- **New drift guards in doctor** (52 checks): skills-index parity
  (`system/skills/` ↔ `system/skills.md`), YAML well-formedness of all
  frontmatter blocks, reverse top-level inventory in `check-architecture.sh`,
  and pointer/reading-list sync.
- Unit tests for the security-relevant Pi extensions (git-interceptor,
  incognito-guard) and addon-CLI regressions — 164 addon tests, 26 extension tests.

### Changed

- **Docs truth sweep**: `architecture.md` documents the dual-checkout/alias/vault
  symlink model and the `shared/` layer; the skills index is complete (39);
  `reference.md`/`tools.md`/README corrected; one canonical session-start
  reading list. `youtube-knowledge` renamed to `youtube-digest` end-to-end
  (add-on, CLI, public folder — backward-compatible with auto-migration).
- Pi extensions compile under **strict TypeScript** and follow the
  **pi-ai 0.80 compat entrypoint** for `complete()`.
- Release channel defaults to **tag mode**; `codex` added to the canonical
  addon client list; `/onboard` vault-anchored with essential addons first.

### Fixed

- **uninstall.sh data safety**: block-based pointer removal (user content
  survives), `AGENTBRAIN_HOME` honored everywhere, multi-checkout alias guard,
  verified JSON edits, a "Left in place" summary.
- **Setup connectors**: OpenCode `instructions` array, Cline's own rules file,
  Windsurf root detection, exit-2 tool detection; bun/uv installers pinned;
  `configure-pi.sh` asks before installing.
- **Update flow**: repo resolution via the `~/agentBrain` alias; one documented
  `auto_update` cascade (missing file → `off`, missing key → `ask`).
- Thirteen skill bins resolve the brain root script-relative; stale pi-lens
  review selection; release tooling (publish zip path, changelog insertion
  order, maintainer tooling stripped from the payload); doctor `--ci` scopes
  `check-explainers` to the public themes.


## [v1.6.1-prerelease-05] - 2026-07-01

### Fixed

- `check-architecture.sh` failed doctor in every fresh install from a release
  archive: the backticked-path check flagged the dev/release tooling that
  `release.sh` intentionally strips from the payload (`deploy-dev-to-live.sh`,
  `release-check.sh`, …). The documented dev-only set is now tolerated when
  absent; the dev checkout still verifies it. Found by `release-check.sh` —
  the v1.6.1-prerelease-04 archive is superseded by this build.

## [v1.6.1-prerelease-04] - 2026-07-01

### Added

- **Skills-index parity check.** New `scripts/check-skills-index.sh` enforces two-way
  parity between `system/skills/` and the `system/skills.md` index (which had silently
  dropped ~18 of 39 skills); wired into doctor (52 checks).
- Unit tests for the security-relevant Pi extensions: git-interceptor's `--no-verify`
  blocking and incognito-guard's write-guard decision logic (14 cases), plus an
  addons-CLI regression test for `disable` on unknown ids (164 addon tests total).
- `test-space-boundary.sh` provisions a throwaway git-inited vault when `local/` is not
  a git repo, so sandboxes and fresh installs exercise the seal-breach scenario.

### Changed

- **Docs truth sweep.** `architecture.md` now documents the dual-checkout/alias/vault-symlink
  model and the `shared/` knowledge layer, and its stale claims are corrected; one canonical
  session-start reading list (the installed pointer), guarded by `check-rules-pointer-sync.sh`;
  `reference.md`/`tools.md`/README refreshed; `check-architecture.sh` gained a reverse
  top-level inventory check and now also path-checks README and reference.md.
- `youtube-knowledge/` renamed to `youtube-digest/`; README addon table regenerated from
  `system/addons/` (ghost entry dropped); devbox pilot plan moved to the private vault.
- Pi extensions compile under strict TypeScript (`strict: true`); the legacy `as any`
  casts on the Pi event boundary use the typed overloads.
- `codex` added to the canonical addon client list; `clients.md` regenerated.
- `/onboard` anchors every command at the vault, promotes the essential addons first,
  derives locale choices from `_strings.sh`, and documents the `auto_update` cascade.

### Fixed

- **uninstall.sh data safety:** pointer-block removal is block-based (user content after
  the block survives, timestamped backups kept); shell-rc cleanup honors `AGENTBRAIN_HOME`
  (a sandboxed uninstall edited the real `~/.zshrc`); the `~/agentBrain` alias and `brain`
  symlink are only removed when they resolve to the checkout being uninstalled; python JSON
  edits are verified; a "Left in place" summary lists what uninstall keeps.
- **Setup connectors:** OpenCode writes the `instructions` array in
  `~/.config/opencode/opencode.json` (the old `system_prompt` key was never read); Cline
  gets its own `Rules/agentBrain.md` instead of overwriting `.clinerules`; Windsurf writes
  into the detected root; Claude/Gemini connectors exit 2 when the tool is absent.
- **Update flow:** default repo resolves via `readlink` of the `~/agentBrain` alias; one
  `auto_update` cascade (file missing → `off`, key missing → `ask`, seed `ask`).
- **check-space-boundary.sh fail-open:** `git grep` in a non-git checkout (release payload,
  install sandbox) errored silently and passed the leak scan; plain-grep fallback added.
- **check-pi-lens.sh** selects the latest review by filename timestamp instead of mtime
  (equalized mtimes kept reporting four already-resolved issues as open).
- Thirteen skill bins resolve the brain root script-relative instead of hardcoding
  `~/agentBrain` (fixes `test-list-space` in the validate-install sandbox).
- Release tooling: `publish-gitea-release.sh` zip path aligned with `release.sh` output;
  `bump-version.sh` inserts new sections below `[Unreleased]`; mktemp scratch files.
- bun/uv installers pinned; `configure-pi.sh` asks before installing Pi/opensrc.


## [v1.6.1-prerelease-03] - 2026-06-27

### Added

- **Spaces — sealed per-owner compartments (Phase 1).** A new first-class layer at
  `local/spaces/<slug>/` for employer/client knowledge: kept out of the personal sync
  (gitignored) and excluded from default recall (`brain_search`/`brain_recent`). Each
  space carries an `index.md` paspoort (`type: space`, a stable `space-id`, plus `owner`,
  `relation`, `sync`, `code-roots`). Write into a space with `new-note.sh --space <slug>`
  (slug path-escape-guarded, path-correct UUID5); view a space with `list-learnings` /
  `list-projects --space <slug>`; deliver a whole space as a portable, `space-id`-stamped
  package with `brain-extract --space <slug>` and re-import with `brain-restore` (confined
  to `local/spaces/<slug>/`, with path-traversal refused). Per-space backup remotes, a
  leakage boundary-guard, and an active-space mode are planned (Phase 2-3).

## [v1.6.1-prerelease-02] - 2026-06-26

### Changed

- **Renamed the `youtube-knowledge` add-on to `youtube-digest`** (CLI `yt-knowledge` →
  `yt-digest`, data dir `local/youtube-knowledge/` → `local/youtube-digest/`, config dir
  `local/addons/youtube-knowledge/` → `local/addons/youtube-digest/`). The name now reflects
  what the add-on does — condense long videos into summarized, searchable notes — instead of
  the generic "knowledge".
  - **Backward-compatible.** The old CLI/skill names still work: `yt-knowledge` is a symlink
    to `yt-digest`, and `/yt-knowledge` remains as a deprecated skill alias.
  - **Auto-migration.** On first run the `yt-digest` CLI renames a consumer's existing
    per-machine `youtube-knowledge` config/state/data dirs to the new slug and repairs the
    absolute filepaths in `state.json`/`learnings-index.json`. Idempotent; a no-op on brains
    that never used the add-on or are already migrated. No manual action required.

## [v1.6.1-prerelease-01] - 2026-06-24

### Fixed

- Default the release channel to **tag mode** (was branch mode): the public repo is a
  single-branch clean snapshot, so the `stable` channel now resolves to the latest
  `vX.Y.Z` tag instead of a non-existent `stable` branch.
- `publish-agentbrain-github.sh` refuses to publish a prerelease VERSION — the public
  GitHub mirror ships stable snapshots only; prereleases stay on the Gitea dev remote.

## [v1.6.0] - 2026-06-24

First stable release of the 1.6.0 line and agentBrain's public launch. Consolidates
the `1.6.0-prerelease-01..06` cycle; per-change detail is in the prerelease sections
below. Highlights:

### Added

- **Add-on-provided skills across every agent.** An add-on that ships a `SKILL.md`
  becomes a usable skill in each detected agent (Claude Code, Copilot CLI, Pi) while it
  is enabled — `addons.sh enable/disable/uninstall` are the lever — and `doctor` enforces
  the invariant (`check-skill-links.sh`).
- **`shared/` knowledge layer** — a third, shareable layer alongside private `local/`,
  with a bidirectional secret-gate, abort-on-conflict rebase, and an id-regenerating
  promote (`setup-shared-vault.sh`, `sync-agentbrain-shared.sh`, `promote-to-shared.sh`).
- **Platform-aware setup** (`scripts/platform.sh`: os/arch/id detection + capability
  probes) and an add-on **`onboard:`** lifecycle hook.
- **`incognito` add-on** (read-only, write-suppressing sessions) and symmetric
  `uninstall.sh` for the bundled add-ons.
- Public-launch hardening: `SECURITY.md`, a rewritten welcoming README, and the
  Apache-2.0 license.

### Changed

- `addons.sh update` re-runs the new version's install step and restores enabled state.
- Addon-skill linking unified in `scripts/lib/skills.sh` — the Claude/Copilot and Pi
  installers share one implementation.

### Fixed

- Add-on lifecycle + portability: `uninstall` prunes skill links; `test` validates local
  add-ons; launchd resolves via dual-root and warns on dropped cron constraints; portable
  sha256; a SIGPIPE-guarded version probe; and a serialized pre-push `doctor` gate.

### Security

- `publish-addon.sh` keeps `GITEA_TOKEN` out of the process list (curl `--config`), and
  `release.sh` ships a tracked-files allowlist with a leak gate.

## [v1.6.0-prerelease-06] - 2026-06-23

### Added

- **Add-on-provided skills across every agent.** An add-on that ships a `SKILL.md`
  now becomes a usable skill in each detected agent (Claude Code, Copilot CLI, Pi)
  exactly while it is enabled — `addons.sh enable/disable/uninstall` are the lever.
  Linking is enabled-gated and enforced by `check-skill-links.sh` in `doctor`
  (enabled ⇒ linked, disabled ⇒ no orphan). Previously an add-on's skill was never
  installed for any agent unless wired by hand.
- `shared/` knowledge layer — a third, shareable layer alongside private `local/`, backed
  by its own git repo. `setup-shared-vault.sh` establishes it with a tiered, host-agnostic
  remote flow (BYO `--remote` / `--bootstrap` a local bare repo); it does not install a git
  server. `sync-agentbrain-shared.sh` syncs with a **bidirectional secret-gate**
  (`check-agentbrain-shared.sh`, pre-push tree scan + `--incoming` scan of fetched refs) and
  rebases with abort-on-conflict (never force). `promote-to-shared.sh` moves a note or folder
  from `local/` to `shared/`, regenerating its path-derived UUID5 and logging a reversible
  old→new id map. `doctor` runs the shared gate when a `shared/` layer is configured and skips
  it cleanly otherwise. Docs: `docs/shared-vault.md`. Design + plan in `local/specs/`.
- `SECURITY.md` (private reporting via GitHub Security Advisories + a "what agentBrain
  touches" section) and README "this is / this is not" + "What it writes & network
  behavior" sections, toward a credible public launch.

### Changed

- `addons.sh update` now re-runs the new version's install step and restores enabled
  state after download (previously the files were updated but install hooks and skill
  links were left pointing at the old version).
- Addon-skill link/prune logic extracted to a shared `scripts/lib/skills.sh`, sourced by
  both the Claude/Copilot installer (`setup-skills.sh`) and the Pi installer
  (`configure-pi.sh`) so the two can't diverge.

### Fixed

- `addons.sh uninstall` now prunes the add-on's skill links (true inverse of install/enable).
- `addons.sh test` validates local/downloaded add-ons against their own registry root,
  instead of silently passing them as "valid".
- `setup-addon-launchd.sh` resolves the addon dir via dual-root, so a registry-installed
  scheduled add-on can get a launchd job; it also warns when a `*/N` cron drops calendar
  constraints (e.g. a weekday restriction) instead of silently altering the schedule.
- `setup.sh`: guard `pi --version | head` against SIGPIPE under `pipefail`.
- Portable sha256 (`shasum` or `sha256sum`) in `addons.sh` and `package-addon.sh`.
- onboard skill: idempotent, backed-up shell-rc write and first-run-safe `config.json` edit.
- Hygiene: `addons.sh configure` validates numeric menu input; the English "newest" marker
  replaces a hardcoded Dutch string; `onboard:`-hook guards a missing `platform.sh`.
- `pre-push` hook serializes the `doctor` gate with a portable lock, ending the
  auto-push / manual-push race that produced spurious "push FAILED".

### Security

- `publish-addon.sh` passes `GITEA_TOKEN` via a mode-600 curl `--config` file instead of
  `-H "Authorization: …"` on the command line, keeping it out of the process list.

## [v1.6.0-prerelease-05] - 2026-06-19

### Added

- `brain version` (bare subcommand) as an alias for `brain -v` / `brain --version`.
  The flag forms already worked; the bare word fell into the unknown-command
  branch. Listed in `brain --help` COMMANDS and `system/tools.md`. (To check for a
  newer release on your channel, `brain-update.sh --check` already reports it.)

### Changed

- License changed from MIT to **Apache-2.0** ahead of the public release.
  See `LICENSE`.
- Rebrand legacy org references in the public layer to `frontmatters` (CHANGELOG
  release links, the `publish-*` / `check-release-published` scripts' `GITEA_OWNER`
  default, and the addon-registry URLs in `specs/`).
- Genericize a hardcoded machine-name example to `a home-server` in the event-bus
  storage SPEC.
- Slim the hot `system/rules.md`: move the path env-var (`AGENTBRAIN_DIR` /
  `AGENTBRAIN_HOME`) definitions and the forward-ref-marker detail to
  `system/reference.md` (progressive disclosure -- smaller always-loaded context).

### Fixed

- `peer-review --list` on an empty bus: `brain-poll` exits 1 as its "no events"
  signal, which under `set -o pipefail` aborted the whole read-only list. A
  zero-result list is valid, not an error -- the poll step now tolerates the
  empty-bus exit. (Surfaced as the `--list errored` skill-test failure.)

### Security

- `release.sh` built the archive from the whole working tree minus a denylist, so
  any stray in the checkout root (tool screenshots, machine-local agent config and
  override files, runtime logs) could ship in the public zip. The payload is now an
  allowlist driven by `git ls-files` (tracked files only, minus dev tooling and
  registry-distributed addons), with a redundant leak gate that aborts the build if
  any untracked file reaches the payload. Playwright-mcp page dumps are also
  gitignored. Build dropped from a stray-bloated 3.5M to ~0.8M.

## [v1.6.0-prerelease-04] - 2026-06-17

### Fixed

- `capture-tool-info`: route physical machines/hosts/devices to
  `local/devices/` instead of `local/integrations/`. The routing table had no
  destination for a host, so a Raspberry Pi was captured as a duplicate
  integration note. Adds a devices row, lists hosts/SBCs/NAS in the trigger
  section, extends the `type` enum with `device`, and documents the
  device-specific frontmatter (intent + state blocks).

## [v1.6.0-prerelease-03] - 2026-06-17

### Added

- `incognito` add-on: read-only brain sessions that suppress all writes
  (learnings, projects, troubleshoot, memories, journal). Enforcement reaches
  the MCP write point and Pi, with behavioural coverage for hook-less agents.
- `ask` `auto_update` mode in `brain-update` — when an update is available, it
  asks before applying (TTY y/N prompt, or an agent-neutral line in a hook
  session). This is the install default.
- Symmetric `uninstall.sh` (true inverse of `install:`) for `agent-browser`,
  `routa`, `sitescope`, `youtube-knowledge`, `secrets-helper`, and
  `agentbrain-mcp`. `check-addons` now fails any add-on shipping `install.sh`
  without a matching `uninstall.sh`.
- Event-bus garbage collection (`brain-events-gc`).
- Optional `platform` frontmatter field for notes.

### Fixed

- `event-bus`: doctor no longer hangs; added GC.
- `offboard`/`import-offboard`: closed scope and rollback gaps; added
  `--include-organization` (symmetric with `--include-team`).
- `setup-local-vault`: halts cleanly on a dangling `local/` symlink instead of
  failing cryptically later.
- `brain-update`: restores the branch on rollback and derives the release
  commitish from the branch.
- `peer-review` `test.sh` is sandboxed so it never writes to the live event-bus.
- `onboard` skill synced to the real update modes (`ask`/`notify`/`auto`/`off`);
  removed stale references to the retired `voice` add-on.

## [v1.6.0-prerelease-02] - 2026-06-14

### Added

- `secrets-helper` integration add-on: a thin, agent-agnostic installer for the
  macOS keychain `secrets-helper` (brew-first, public git-clone fallback,
  idempotent, macOS-guarded).
- `os` platform axis in the add-on manifest schema (`macos|linux|windows|any`,
  absent = cross-platform), validated by `check-addons.sh`, documented in the
  add-on README, and rendered as a column in the generated `clients.md` matrix.
- `unpark`: render a Markdown table of paused/blocked projects (newest first,
  numbered, full status) when called with no argument.
- Release advisory guard (`check-release-published.sh`): reminds at deploy time
  when a bumped VERSION has no published release.
- `still-needed` add-on + `/relevant` skill: per-item relevance check across
  parallel sessions ("is this open work already resolved elsewhere?").

### Changed

- `configure-pi.sh` now delegates `secrets-helper` installation to the add-on
  instead of a hardcoded block (closes the long-standing TODO; the legacy
  `SECRETS_HELPER_REPO` opt-in is preserved).
- `uxray` 0.1.1: added the "Absolute bans" auto-fail canon and AI-slop test;
  reframed as a self-contained, multi-platform methodology.

### Fixed

- `registry-index.sh`: keep only the highest-version zip per add-on id, so a
  stale older build can no longer win the index entry (avoids `ls`, SC2012-clean).
- `check-doctor.sh`: exempt advisory deploy-time checks (e.g.
  `check-release-published.sh`) from the orphan gate, so doctor stays green.
- `check-architecture.sh`: treat `local/*` paths as optional (user runtime
  state, absent in a fresh install) so doctor passes on a clean install.
- `test-addons.sh`: skip the maintainer-only publish-script regression guards
  when those scripts are excluded from an end-user install archive.

## [v1.6.0-prerelease-01] - 2026-06-13

### Added

- Addon registry (Docker/npm-style): static `index.json` registries with a
  per-machine **default** registry plus addable named registries
  (`addons.sh registry default|add|remove|list`). `search`/`install`/`update`
  resolve across them; installs verify `sha256`. Dupe rules: newest wins within
  a registry, the default registry beats named ones (dependency-confusion
  guard), explicit `<registry>/<id>` pin overrides.
- Dual-root addon discovery: bundled (`system/addons/`) + local
  (`local/addons/`); `status` gains VERSION/SOURCE columns, `--remote` adds an
  UPDATE column. `addons.sh new <id>` scaffolds an addon into `local/addons/`.
- Slim-core installer: `scripts/release.sh` ships only essential addons
  (`scripts/lib/essential-addons.txt`); the rest distribute via registries.
- Distribution tooling: `package-addon.sh` (privacy-scanned zip + sha256),
  `registry-index.sh` (generate index, validates URLs), `publish-addon.sh`
  (Gitea release + index), `mirror-registry-github.sh` (gated public mirror).
- `privacy-scan.sh --dir <path>` and `--git-identity <repo>` modes; offboard
  export/import now includes a `config/` section (registries, default-url,
  enabled addons, locale).

### Changed

- Renamed the primary-registry concept `official` → `default` (npm/cargo
  convention); index self-name `agentbrain-official` → `agentbrain`.
- The default registry is always resolved dynamically (env >
  `local/addons/default-url` > baked GitHub default); `registries.json` holds
  only named registries, so re-pointing the default never goes stale.

## [v1.5.6-prerelease] - 2026-05-20

### Added

- `scripts/install-prerequisites.sh` — general developer tools (nvm, Node LTS, Homebrew, bun, uv).
- `scripts/configure-pi.sh` — Pi-specific setup: install Pi, opensrc, extensions, skills, tsconfig, API check, credentials.
- `scripts/bootstrap-macos.sh` — slim macOS orchestrator; replaces `bootstrap-pi-macos.sh` as canonical entry point.
- `scripts/configure-clients.sh` — all AI client pointer installs extracted from `setup.sh`.
- `ensure_bun` and `ensure_uv` in `install-prerequisites.sh`.
- 6 skills added to `system/skills.md`: `capture-tool-info`, `refactor-brain`, `opensrc`, `lightpanda`, `understand`, `understand-project`.
- `opensrc` skill added to `.github/skills/` for Claude/Copilot/Gemini.
- `scripts/configure-clients.sh` added to lifecycle contract check.
- Gemini CLI pointer support in `setup.sh`, `uninstall.sh`, `move-agentbrain.sh`.
- Extended doctor to 15 checks: preference scopes, node bootstrap, lifecycle scripts, client pointers.
- Scoped preferences: `local/preferences/personal/`, optional `organization/` and `team/`.
- `/onboard` skill updated for personal-first scoped preference flow.

### Changed

- `bootstrap-pi-macos.sh` is now a thin backwards-compat redirect to `scripts/bootstrap-macos.sh`.
- `setup.sh` reduced from 484 to 269 lines by extracting client installs.
- `ensure_pi` moved from `install-prerequisites` to `configure-pi` (Pi is a client, not a dev tool).
- `scripts/readme-lightpanda.md` moved to `system/integrations/lightpanda.md`.
- All stale `bootstrap-pi-macos.sh` references updated across docs and scripts.
- README Quick Start updated: `./setup.sh` for everyone, `scripts/bootstrap-macos.sh` for macOS+Pi.
- `lightpanda-install-wrapper.sh` fixed: was hardcoded to `~/Developer/agentBrain/Scripts/`.

### Fixed

- `ensure_opensrc` regression: accidentally removed when extracting `ensure_pi`.
- Duplicate section numbering in `setup.sh` (two sections labelled "5").
- Stale comment "must match bootstrap-pi-macos.sh setup_local_structure".
- `docs/` empty directory removed.


### Added

- Reproducible Pi extension type-check and helper-test scripts integrated into doctor.
- Unit tests for brain path safety, session archive target selection, and YouTube VTT cleanup.
- `doctor.sh --pi-lens-strict` release-quality mode.

### Changed

- Hardened `brainPath(...)` to reject traversal outside the agentBrain root.
- Extracted YouTube transcript helper utilities and simplified markdown writer options.
- Hardened pi-cloak dynamic regex compilation with length and flag validation.

## [v1.5.1] - 2026-05-18

### Fixed

- Pi `brain-paths.ts` helper now exports a no-op default factory so Pi can auto-load the helper file without extension startup errors.
- Bootstrap now links helper modules required by Pi extensions, preventing missing `./brain-paths` imports in `~/.pi/agent/extensions/`.

## [v1.5] - 2026-05-18

### Added

- Doctor `--ci`, `--summary`, `--verbose` flags
- CI workflow calls `bash scripts/doctor.sh --ci` for full parity with local checks
- `CHANGELOG.md` following Keep a Changelog format

### Changed

- `brain.json` path field now uses `~` instead of absolute home directory path
- CI workflow uses single `doctor.sh --ci` command instead of duplicated check list

### Fixed

- Doctor check counter now correctly tracks passed/failed checks in all modes
- Compact default output (path-naming details only in `--verbose`)

## [v1.4] - 2026-05-18

### Added

- Doctor health audit system (`scripts/doctor.sh`) with 10 automated checks
- `scripts/check-readmes.sh` — README coverage for public markdown folders
- `scripts/check-frontmatter.sh` — UUID5/date/type/tags validation
- `scripts/check-session-schema.sh` — session naming convention validation
- `scripts/check-links.sh` — wiki-link target validation
- `scripts/check-path-naming.sh` — path naming drift report
- `scripts/check-pi-lens.sh` — unresolved Pi-lens worklog findings
- Doctor `--ci`, `--summary`, `--verbose` flags
- Session continuity system with crash recovery
  - `local/sessions/session-journal.md` (live journal)
  - `local/sessions/archive/YYYY-MM/YYYYMMDD-HHMMSS-<pid>.md` (archived)
  - Random 4-hex PID with retry-on-collision
- Pi session-continuity extension (`system/pi-config/extensions/session-continuity.ts`)
- README documentation for all 24 public markdown folders (was 0, now 24/24)
- GitHub Actions CI with privacy scan, all health checks, and ShellCheck
- `.github/skills/doctor/` skill (SKILL.md + README.md)
- ShellCheck integration for all shell scripts
- Session continuity behavior rules in `system/agent-config/shared.md`
- Public docs at `system/sessions.md`

### Changed

- `brain.json` path field now uses `~` instead of absolute home directory path
- All public frontmatter UUIDs normalized to proper UUID5 (was string slugs)
- CI workflow now calls `bash scripts/doctor.sh --ci` for parity with local doctor
- `setup.sh` generates `brain.json` with relative `~` path

### Fixed

- `session-continuity.ts`: removed await-in-loop, added targeted Pi-lens suppressions
- Git history cleaned of private data (IPs, hostnames) via `git-filter-repo`
- Missing `tags` fields added to project example files
- TypeScript check passes with `ignoreDeprecations: "6.0"`

### Security

- GitHub repo made public after thorough privacy audit
- Privacy scan catches secrets, tokens, private IPs, and personal identifiers
- `brain.json` no longer leaks absolute home directory path

## [v1.3] - 2026-05-16

### Added

- `/brain-review` learning required fields checklist
- A+ fixes: consistency, clone URL, frontmatter, maintenance routine

### Fixed

- Consistency improvements across documentation

## [v1.2] - 2026-05-15

### Added

- `setup.sh`: explicit WSL detection + platform banner

### Fixed

- Remaining audit issues for A grade
- Frontmatter consistency in README.md and CLAUDE.md
- Cross-platform, non-interactive, and error handling improvements
- Obsidian community plugins in .gitignore

### Changed

- VS Code: detect Code-Insiders + VSCodium
- README: Obsidian as first-class citizen

## [v1.1] - 2026-05-14

### Added

- `local/` personal layer with bot integration and dev loop learnings
- Project subfolders, PDCA lifecycle, and project templates
- Cross-agent skill support via `system/skills.md`
- `/onboard` skill with resumable interactive setup
- Seamless setup: `scripts/setup.sh` installs global agent pointers
- Windsurf IDE support (`.windsurfrules`)
- OpenCode support
- GitHub Action for automatic version updates

### Changed

- Personal data routed to `local/` across all agent configs
- `setup.sh`: auto-install dependencies (git, python3, Obsidian)

### Fixed

- Audit issues: Dutch text, UUIDs, onboarding message, session default
- Cross-platform, non-interactive, Claude dir creation

## [v1.0] - 2026-05-13

### Added

- Initial public agentBrain framework
- Multi-agent support (Claude, Copilot, Windsurf, Cline, Cursor)
- `system/rules.md` with public/private separation
- `learnings/`, `projects/`, `templates/`, `sessions/` structure
- MIT License

[v1.5.2]: https://github.com/frontmatters/agentBrain/compare/v1.5.1...v1.5.2
[v1.5.1]: https://github.com/frontmatters/agentBrain/compare/v1.5...v1.5.1
[v1.5]: https://github.com/frontmatters/agentBrain/compare/v1.4...v1.5
[v1.4]: https://github.com/frontmatters/agentBrain/compare/v1.3...v1.4
[v1.3]: https://github.com/frontmatters/agentBrain/compare/v1.2...v1.3
[v1.2]: https://github.com/frontmatters/agentBrain/compare/v1.2...v1.1
[v1.1]: https://github.com/frontmatters/agentBrain/compare/v1.1...v1.0
[v1.0]: https://github.com/frontmatters/agentBrain/releases/tag/v1.0
