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

## [v1.10.12] - 2026-09-07

### Fixed

- `brain update` on the stable channel (tag mode) fast-forwards the current branch to the release when it descends from HEAD; before, tag mode never fast-forwarded and every update asked for `--switch`. A release cut since the last update is also taken by this run: the channel is resolved again after the fetch.
- Seven places used bash 4 constructs (`declare -A`, `mapfile`, `${x,,}`) that macOS `/bin/bash` 3.2 cannot run: the event-bus install, `addons.sh config`, `report-stale` (red on every fresh Mac), the Pi wrapper, the wiki-link crawler and the space-docs validator. All run on bash 3.2 now; `dev-registry.scan.sh` states its bash 4 requirement and re-execs on Homebrew bash.

### Added

- `check-bash32` refuses bash 4 constructs in code that runs on an install, since `bash -n` on bash 5 cannot see them.

## [v1.10.11] - 2026-09-07

### Changed

- New addons are built on a branch or worktree and enter `system/addons/` on `main` only once `check-addons` passes; releases are cut from `next`, never from the working tree of dev (docs/development.md).

### Fixed

- The doctor ended in silence right after a red check whose output had no keyword (check-onboarding, test-report-stale) on every machine with BSD or GNU grep: an empty grep under pipefail failed the reason assignment and `set -e` stopped the run. The reason pipeline tolerates an empty match now; `test-doctor-reason-block` proves it with the system grep.
- setup refuses an existing `~/agentBrain` that is not an agentBrain checkout (an old install, a vault cloned there by mistake) and says how to fix it; before, every skill link and client pointer was written through it and the doctor failed in 29 places on a machine with such a leftover.

## [v1.10.10] - 2026-09-07

### Fixed

- `check-frontmatter` died under macOS `/bin/bash` 3.2 ("no closing `)`" on a multi-line `if` inside a process substitution), so every install on a Mac without Homebrew bash went red. The doctor now runs each check under its own shell, so a run with `/bin/bash` exercises bash 3.2 everywhere.
- `brain` (and every script that sources the prompt helper) resolves its own symlink first. Through `~/bin/brain` it looked for `~/bin/installer/prompt-helper.sh` and every command died on line 16.
- `addons.sh install` ran `install: none` as a shell command and failed with "none: command not found" (goal, lottie-animator, web-interface-guidelines). `none` means no install step.

## [v1.10.9] - 2026-09-06

### Added

- The installer refuses to run over a factory checkout (a `factory.json` beside the resolved target, also through the `~/Developer/agentBrain` proxy link) and points to `brain use dev|live`. Twice in one evening it had reset the factory's live checkout to the published snapshot.

## [v1.10.8] - 2026-09-06

### Fixed

- launchd templates logged to `local/logs/`; they log to `vault/logs/` now.
- extract-learnings, youtube-digest, llm-config, the MCP incognito flag and the Pi startup context resolved the private layer as `<checkout>/local/`. They now fold to `vault/` (`local/` on an older install), so a checkout no longer regrows a real `local/` beside the vault link, extracted learnings land in the vault, and llm-config finds the user config.
- `check-frontmatter` in a release payload (no git) validates the framework's own trees and the root files it ships; a stray root file left by an earlier lineage failed the publish gate.

### Changed

- check-vault-spelling also refuses the `join(root, "local", ...)` spelling. `brainPath(` calls and test fixtures stay exempt: they spell the identity by design.

### Added

- `setup-launchd-lan.sh` renders and loads the two LAN launchd jobs of a factory host (git daemon, lan-install) from their templates, with `--uninstall`; `uninstall.sh` boots them out. Until now they were rendered by hand, which is how they kept logging to `local/logs/`.

## [v1.10.7] - 2026-09-06

### Fixed

- The doctor under the installer hung on `test-ask_or_forward` on two machines: the installer hands its children `/dev/tty`, and the prompt helper reads when stdin is a terminal. Every check now runs with stdin closed and with `GIT_CEILING_DIRECTORIES` at the checkout's parent (a checkout inside another repository read that repository's ignores); the test closes stdin itself. `check-frontmatter` validates tracked files only, so a stray root file from an earlier lineage is not the framework's to judge.
- An update of a checkout that carries a real `local/` directory from before the `vault/` rename no longer turns `check-readmes` and `check-frontmatter` red: both skip `local/*` like `vault/*`, and `setup-vault` sets such a leftover aside next to the checkout (never merged, never deleted) and says where. The release gate now runs a sixth step, a doctor over a checkout with exactly those leftovers; a fresh-install sandbox had proved nothing about an update.

## [v1.10.6] - 2026-09-06

### Changed

- A red check in the doctor's summary always shows its reason (the check's own FAIL lines, else the tail of what it said) and a `└ open:` line with the exact command to run it by hand. The doctor and the installer banner print their context first: checkout, vault, cwd, TMPDIR, `AGENTBRAIN_HOME`, bash and git versions, platform. A pasted output is self-describing now; a red cross on another machine used to arrive without a reason. Installer unit 0.2.5.
- Five scripts lose the word `local` from their name: `check-vault-private` (was check-agentbrain-local), `check-vault-content` (check-local-content), `setup-vault` (setup-local-vault), `sync-vault` (sync-agentbrain-local), `test-sync-vault-cli`. The old names stay as symlink shims beside them, so hooks and habits keep working.

### Fixed

- `test-vault-lib` was red on every macOS install through the installer and green everywhere else, for hours. The cause: `scripts/installer/bootstrap/macos.sh` exports `AGENTBRAIN_DIR` and then runs `setup.sh`, whose doctor inherits it; a fixture test then resolved the vault to the real checkout instead of its fixture, and the 1.10.5 summary filtered the `FAIL[…]` lines away. The doctor now strips the caller's brain-location variables (`VAULT`, `AGENTBRAIN_DIR`, `AGENTBRAIN_VAULT_DIR`, `AGENTBRAIN_LOCAL_DIR`, `BRAIN_DIR`, `BRAIN_ALIAS`) for every check, `check-onboarding` finds its checkout by its own location (it read setup's exported `VAULT`, which turned `test-check-onboarding` red in the release gate), the two tests clear those variables themselves, and `test-env-hygiene` runs five fixture tests with `VAULT` and `AGENTBRAIN_DIR` pointing elsewhere.

- A space is confidential by definition: `check-space-boundary` refuses `confidential: false` and any `display:` name on a space. The previous rule allowed a readable name on a non-confidential space, which contradicted `rules.md` (reusable knowledge belongs in the shared vault) and `docs/spaces.md` (`confidential: true`, always). Measured once: a review of a public project sat in such a space with `sync: none` and no backup.
- `check-doctor` now also refuses a `test-*.sh` that is not wired into the doctor. 18 of 57 tests were not, six of them red for weeks: fixture paths still spelled `local/` (`check-onboarding`, `configure-pi-skills`, `report-stale`, `security-defaults`, `brain-explain`, `claude-memory-redirect`, `shorthand`, `graphify`), a `ROOT` that resolved through the `scripts/` symlink shim into the factory (`addons-release`, `abh-integration`, `check-cmdb-coverage`), and manifest `test:` lines that were not relative to the addon (`llm-config`, `pubcheck`). All 56 run in the doctor now; `test-addons-release` stays the release gate's.
- The youtube-digest coverage gate stood at 75% and had never been reached (35% on v1.10.1); it reads bun's `% Lines` column and now sits on the measured 67%, a ratchet from here. `resolveVaultDir` in `extract-learnings.ts` makes the `vault/` versus `local/` choice testable.
- Skill pruning for Pi (`skills.sh`) accepts a skill under `local/skills/` on an install setup has not touched, instead of pruning it as orphaned.

## [v1.10.5] - 2026-09-06

### Changed

### Fixed

- `addons.sh` fetches the registry index with `Cache-Control: no-cache`; raw.githubusercontent.com caches it for 300 s and an install right after a publish got the previous version.
- `test-edge-identity` skips on a checkout that cannot build a bundle from `main` (shallow, or no `main` branch).
- A checkout can switch between the LAN installer and the online installer, both ways, and still name its release. The two lineages share tag names on different commits; a plain tag fetch refused the same-named tag in silence and `git describe` yielded a bare hash. `scripts/lib/lineage.sh` (`adopt_lineage`) makes the chosen source win: forced tags, pruned tags, verified `describe`. Both installer paths and `brain-update.sh` use it; `test-lineage-switch.sh` pins all four directions, bundles included. Installer unit 0.2.4.
- The installer's update of an existing checkout fetches the tags too, forced: a checkout that once tracked the private lineage holds same-named tags on other commits, and a plain tag fetch refused them in silence. The public repo is a rewriting snapshot, so a checkout's old tags never sit on the new lineage; without the new ones `git describe` gave a bare hash and `test-edge-identity` failed on every updated consumer install. Installer unit 0.2.3.

## [v1.10.4] - 2026-09-06

### Fixed

- The installer banner showed the version of whatever `VERSION` file sat in the caller's working directory when run through `curl | bash` (`BASH_SOURCE` is empty there). It now reads the file beside the script when there is one, otherwise fetches `scripts/installer/VERSION` from the same branch the code comes from, and says `unknown` offline. Installer unit 0.2.2.
- `brain-explain` cards: a wrapped list item kept only its first line; continuation lines now join the item above them.

## [v1.10.3] - 2026-09-05

### Fixed

- A checkout mounted on a populated vault adopts the vault's UUID5 namespace in `setup-brain-config.sh`, before templates and the daily note are rendered; the vault's namespace backup is never rewritten. A checkout with its own namespace had seeded 13 template notes into the shared vault with ids no validator accepts. Obsidian machine state (`workspace.json`, `graph.json`) no longer ships as a vault seed.

- The GitHub snapshot of 1.10.2 shipped without `templates/vault/`: an unanchored `vault/` in `.gitignore` also hid that directory from the snapshot commit. Root-anchored now (`/vault/`, `/local/`).
- CI doctor differed from a workstation: `check-agnostic` died on a broken pipe and, without ripgrep, used a hand-kept exclude list that had drifted (228 hints); the grep fallback now derives its excludes from the same globs and both engines scan the same file types. The doctor's shellcheck step runs at `-S warning` so shellcheck 0.9 on a runner and 0.11 locally report one set; the trap-invoked functions in `setup-local-vault.sh` carry the SC2317 directive. `check-skill-relations` resolves the checkout it lives in (it scanned 0 skills on CI and called that valid).
- The public snapshot commit is a Conventional Commit (`chore(release): agentBrain vX.Y.Z`).

## [v1.10.2] - 2026-09-05

Everything since v1.10.1 (2026-08-15): the 73 candidates for v1.10.2, collapsed
into one section on 2026-09-05 when the changelog became the release body.
Headline: every guard used to sit at the exit and several reported success
while doing nothing; this release adds the checks that were missing at the
entry, moves maintainer tooling into the factory so the public tree holds the
framework and its addons and nothing else, and keeps the vault outside the
checkout on every install.

### Added

- **Project Metro**: a self-contained, zero-dependency project visualizer that turns
  plan milestones into deterministic octilinear SVG metro maps, with pan/zoom,
  station details, phase gates, layout generation and 13 Node tests.
- **Aggregate add-on release gate**: `scripts/test-addons-release.sh` now runs all
  functional add-on suites, TypeScript coverage checks and manifest validation in one
  release-oriented command.
- **ABH integration setup**: optional `setup-abh.sh` configures the ABH web
  profile through its own plugin mechanism with agentBrain context, memory and
  filesystem skill providers.
- **ABH Web launcher and optional autostart**: `brain harness web` starts ABH, while `brain harness autostart enable` uses launchd on macOS and systemd user services on Linux/WSL.
- **Optional macOS credential migration**: Pi setup now offers secrets-helper when plain `auth.json` credentials are detected. Linux and WSL receive a platform-appropriate message instead of a macOS Keychain instruction.
- **Optional Ollama offer**: the setup flow now offers the platform-specific local AI runtime through the reusable capability installer. Open WebUI remains intentionally out of scope.
- **Dependency-free terminal menus**: installer CLI selection now uses one shared semantic key decoder with arrow navigation, Space toggles, Enter/Esc handling, terminal restoration and numeric fallback. This works before Node, Homebrew or any external UI tool is installed.
- **Interactive shell audit**: new scripts/checks/audit-interactive.sh systematically checks every bug class seen in the field (syntax, shellcheck severity, non-ASCII after variable expansions, corrupt UTF-8, set -e sensitive assignments, viewport clears outside the intro, NUL-delimiter key reads, embedded helper drift). Current tree: AUDIT PASS.
- installer: visible WSL version check: `platform_wsl_version()` (layered:
  binfmt WSLInterop → `wslinfo` → kernel-string, immune to the custom-kernel
  false positive that makes nvm/pnpm call a WSL2 distro "WSL 1") shown in the
  bootstrap banner (`flavor: wsl: WSL 2 ✓`); WSL 1 hard-fails before the tool
  step with PowerShell remediation (`wsl --set-version <distro> 2`).
- launchd templates `dev.agentbrain.lan-install` (serves installer + fresh
  bundle on :7780, rebuilt on every login: no more stale-version channel) and
  `dev.agentbrain.git-daemon` (LAN updates origin, supervised + KeepAlive).
- **Workspace `derived/` lane** and `scripts/lib/workspace.sh`, the first
  resolver for `~/.agentBrain/workspace/`. Lanes are named by lifetime:
  `external/` until you are done with it, `derived/` until its producer runs
  again, `scratch/` never mind.
- **`scripts/checks/check-intake.sh`**: refuses zero-width, bidi-control and
  Unicode-tag characters at the moment a note is written (PostToolUse hook)
  and at both commit boundaries. Zero-width residue can be stripped with
  `--fix`; direction controls are never repaired automatically. Measured
  before it existed: 188 such characters in the vault, 175 of them from one
  imported chat archive.
- **Doctor `unreachable code` step**: `shellcheck --include=SC2317` over every
  shell file, with a file walk when there is no git repository (release-check
  runs doctor inside an unpacked zip). Doctor's general shellcheck now covers
  all of `.githooks/`.
- **`scripts/checks/check-shim-staging.sh`**: `git add scripts/doctor.sh`
  stages the symlink, not the file behind it, so a commit can describe work it
  does not carry. pre-commit warns and names the real path; commit-msg refuses
  only when the message claims that file.
- **`scripts/rename-space.sh`**: gives a space a neutral slug (`sp-<hex>`),
  re-deriving every note id and rewriting the slug where it is an identifier
  (`space:` fields, paths, wiki-links, `--space` arguments) and nowhere else.
  `--dry-run` counts what it would touch.
- **`scripts/lib/lock.sh`**: doctor serializes itself. Four of its tests plant
  fixtures in the real vault; two doctors at once tripped over them.
- **`rules.md` "Material from outside"**: route imports through the workspace,
  a note records rather than instructs, invisible characters are refused at
  the entry, provenance travels with the material.
- `scripts/checks/check-source-paths.sh` (doctor): evaluates every `source`/`.`
  line in `scripts/` from the script's own location and fails when the target
  does not exist. Catches the class above before a user does; `bash -n` and
  shellcheck do not.

### Changed

- The `local/` alias of the vault link is retired. Setup no longer creates it; `scripts/setup/drop-local-alias.sh` re-points the agents' skill and memory links from `<brain>/local/` to `<brain>/vault/` and removes the alias from a checkout (inverse: `ln -sfn vault local`). check-anchors warns while it is still there. Skill CLIs under `bin/`, the space scripts, the Claude write hook and the youtube-digest extractor address `vault/`; configs written by an older install (`local/…` in journal, weekly-review and memory-redirect settings) are folded at the consumer. The migration count now scans extensionless `bin/` scripts and `"$X/local"` forms too.
- `check-vault-spelling --count` reports zero: every `local/` left in code is named as identity (the MCP, ids, tests), as a fold or mapping to `vault/`, or as the alias mechanics in setup and uninstall.
- Note paths handed to `new-note.sh`, `queue.sh`, the session journal and the space scripts are spelled `vault/…`; `uuid5-gen.sh`, `check-local-content` and the Pi `pseudoUuid5` all fold that to the `local/…` spelling every id was derived from, so no id changes. The Pi extensions resolve the brain root per call (`brainDir()`) and send `local/…` requests to `vault/` on disk, like the MCP.
- Scripts, checks and addons address the vault as `vault/` on disk (messages, defaults, `find` roots, config paths); globs on physical paths accept both spellings. The MCP reads the vault from `vault/` when it exists and keeps `local/` as the identity of every note.
- Documentation, agent pointers and skill/addon READMEs now name the vault as `vault/` (the checkout link); `local/` is only mentioned where the alias itself is explained. The MCP server accepts `vault/...` paths and folds them to the `local/...` identity every note id and access-index key is built on.

- **Installer**: the optional agent/tool menu now offers `agentBrain Harness` as its
  final option. A missing installation is installed with `npm install -g
  @agentbrain-harness/abh`; an existing installation is updated in place.
- **Runtime contracts**: add-on manifests can declare `runtime_requires`, with
  capability probes for Bun, yt-dlp, Routa and Devbox.
- **YouTube Digest**: sync, adapter, retry, recovery, summarizer and CLI paths now
  expose deterministic test seams; the suite covers 56 scenarios and reaches
  75.39% line coverage.
- **Optional tool ordering**: `agentBrain Harness` is now the first recommended
  optional tool and Pi is the second recommended option.
- **Agent detection**: a config directory alone no longer reports Claude Code as
  installed; the Claude CLI must actually be available on PATH.
- **Runtime declarations**: add-on prerequisite capabilities are now declared in
  manifests and checked through the platform capability layer.
- **LAN installer**: the maintainer-only LAN wrapper now follows the canonical
  website installer flow and runs prerequisite installation before agentBrain setup.
- **Pi setup**: LAN installations no longer skip Pi by default; the deep Pi
  integration runs unless explicitly disabled.
- **Installer transparency**: the installer now displays its own installer version
  separately from the target agentBrain release version.
- **Installer version reporting**: detected agent CLIs now show their current version in the optional tool list, including agentBrain Harness even when the installer follows npm latest.
- **ABH update visibility**: the optional tool menu now compares the installed
  agentBrain Harness version with npm `latest` and reports `up to date` or
  `update available` before the user makes a selection.
- **Installer version display**: installer version and target agentBrain release are now shown on separate lines for unambiguous diagnostics.
- **ABH integration copy**: the optional web-profile prompt now explains the context, memory and skill providers, what changes, and that agentBrain remains canonical.
- **AgentBrain Harness copy**: the integration prompt now spells out the full
  product name, explains context, memory and skills, and states that agentBrain
  remains the source of truth. The short `abh` form remains only in commands.
- **AgentBrain Harness provider versions**: provider installation follows the
  detected harness prerelease family when available, avoiding a silent rc9/rc10
  mismatch.
- **Pi credential warning**: the setup no longer suggests placing API keys in
  shell commands and directs users to the optional Keychain migration instead.
- **Platform-aware offers**: local runtime offers use shared capability detection and remain opt-in, safe in non-interactive mode, and separate from the core agent installation.
- **Unified prompts**: installer confirmations and prerequisite keep/update/skip choices now use the shared semantic prompt helper; the helper is embedded in the standalone installer so website and LAN installs get the same behavior.
- **Complete prompt migration**: first-party prerequisite and onboarding choices now route through the shared semantic prompt helper, including Python onboarding via its standalone CLI interface; the standalone installer embeds the helper.
- **Installer versioning**: when the target is a prerelease candidate, the installer banner shows an rc of the same maturity (for example `installer v0.1.1-rc.39`), making it visible that the installer itself is still being corrected alongside the framework.
- **Numbered menus restored, better**: single-select rows show `1) option` without misleading checkboxes, multi-select rows show `1) [x] option` with direct toggle on 1-9 (Space still works), and confirmations show numbered Yes/No. Arrow navigation, Enter/Esc and all prior fixes are unchanged.
- **Dynamic numeric hints**: menu help lines now show the real selectable range (for example `1-3 navigate`) instead of a hardcoded `1-9`.
- **AB Question API orientation & spec**: questions now carry an orientation: `--default` (preselected row / yes-no side, shown with "(default)"), `--required` (Esc stays in the question) and multi preselection via `--default "1 3"`. View styles (numbered/checkbox/plain/inline) are formalized in the new machine-readable contract `scripts/installer/prompt-api.json`, enforced by test-installer-prompts.sh. A lone ESC followed by another key no longer swallows that key (replay buffer).
- **Configurable question layout**: confirmations now render vertically (numbered Yes/No rows, like every other question) by default, configurable per question via `--layout vertical|inline` and globally via `AB_PROMPT_LAYOUT`.
- **Numbers choose directly**: in single-select menus, pressing 1-9 now immediately selects that option instead of only moving the cursor; Enter still confirms the highlighted row and arrows behave unchanged. Help line updated to match.
- **Agent menu stays in context**: the agent CLI selection no longer clears the viewport; it redraws only its own block in place, keeping earlier choices and the prerequisites scan visible. Rows are numbered and 1-9 toggles a row directly, consistent with the other menus.
- **All install-path questions on one question layer**: setup personalize, git identity (new text question), Homebrew tools, fast-runtime (Ollama), Pi/opensrc, nvm fallback and capability offers now use the shared AB Question API with orientation (`--default yes|no` restores the original [Y/n] vs [y/N] nuances) and the vertical numbered layout.
- **Zero loose prompts left**: the remaining maintenance tools (addons enable/launchd/run/config-picker, uninstall, move-agentbrain, setup-local-vault, lightpanda reinstall, brain menu, brain-update confirm and the release-channel picker) now all use the AB Question API; their old defaults are preserved via orientation flags.
- **Onboarding renders once**: wizard questions no longer print a duplicate option list below the shared menu; descriptions now live inside the menu rows, the detected/default choice is passed through as the menu orientation, multi preselects honour the review screen, and the theme question orders both/dark/light with both as default.
- **Pi install orientation**: installing Pi and opensrc now defaults to Yes (Enter installs), matching their recommended status in the installer flow; every other question default was audited and documented in prompt-api.json orientation_policy.
- **brain harness naming**: `brain harness` (no argument) is documented as the short form that starts the Harness web UI; `brain harness web` remains the explicit form and `brain harness autostart` manages the boot service. Usage text updated.
- **`brain harness` is the command**: shorter and unambiguous; `brain harness web` keeps working as an alias and autostart management stays on `brain harness autostart`. Usage, next-steps output and docs updated.
- **Shorter section heading**: the agent CLI section header is now just "Agent CLIs and tools (optional)"; the Harness-first/Pi-second ordering is communicated by the menu itself (row order + recommended markers), not by a long heading.
- **Offers always available**: present capabilities now get the same maintenance menu as the developer tools: keep (Enter, honest default) / update (runs the brew upgrade recipe non-interactively) / skip; absent capabilities keep the install offer with No as default. Also fixed an if/|| precedence bug where choosing No still ran the "still absent" branch, and a corrupted byte sequence in the update message.
- **No blind skips anywhere**: every optional capability now follows one visible pattern: present → keep / update / reinstall / skip (skip default), absent → install / skip (No default). Added a reinstall row to capability offers, made the secrets-helper menu visible when installed, made the Obsidian offer unconditional, and clarified that update/reinstall coincide for the dev tools.
- **brain CLI polish**: removed the dead `brain voice chat` example (the voice addon no longer exists) and clarified in the help that `brain harness` defaults to the web UI.
- **brain harness lifecycle**: `brain harness` starts the web UI or opens the browser when it is already running; `brain harness stop` is graceful: it stops the autostart login-service first (launchd/systemd KeepAlive would otherwise restart it instantly), then SIGTERMs and waits. Autostart question added to the install flow (No default; when ON a keep/disable menu). Naming made consistent: user-facing copy says "agentBrain Harness" everywhere, "ABH" only in internal file names.
- **Autostart platform coverage**: the autostart offer is agent-agnostic (it starts the agentBrain Harness web UI for every agent reading this brain) and platform-aware: launchd on macOS, `systemd --user` on Linux, and on WSL it now gives a clear hint to enable systemd via /etc/wsl.conf instead of a raw systemctl error.
- **Repeatable interactive audit**: every script is now checked for the bug classes seen in the field; current tree: AUDIT PASS.
- **Capability maintenance menu with daemon lifecycle**: present capabilities offer keep/update/reinstall/skip (skip default); update derives brew upgrade from the install recipe (never a bogus "reupgrade"), reinstall re-runs the install recipe. New per-capability layers: capability_start_cmd (e.g. brew services start ollama) and capability_health_cmd (daemon probe); ensure_running starts and health-checks the daemon after every install/update/reinstall. capability-install.sh rewritten ASCII-only after a corrupt byte caused an unbound-variable crash in the field.
- installer-rollout prep: pre-push auto-repair (symlinks, agent-skill sync)
  and the security-policy wikilink correction; the installer unit itself
  (symmetric bootstrap-<os> dispatch, flow journal) shipped in this line.
- **Maintainer tooling is no longer in this repository.** The release,
  publish, deploy and addon-packaging scripts, their checks and tests, and
  the release acceptance matrix moved to the factory: the directory beside
  this checkout that holds every agentBrain checkout, the archives and the
  addon catalogue. The archive built from this repo is now `git ls-files`
  with nothing to strip; the `NONSHIP_SCRIPTS` exclusion, which had matched
  only compatibility symlinks since 2026-09-01 while the real scripts under
  `scripts/release/` shipped, is gone with the scripts. `scripts/channel.sh`
  (the one consumer command in that directory) moved up to `scripts/`.
  `factory.json` lives in the factory; `factory_root()` looks there.
- **The public tree holds the framework and its addons, nothing else.** The
  vault-shaped top-level directories (`learnings/`, `projects/`, `sessions/`,
  `daily-notes/`, `backlog/`, `youtube-digest/`, `user-preferences/`,
  `.obsidian/`) were placeholders from the era when the public repo was the
  vault layout; they made the checkout look like a vault and invited real
  notes in. They are now seeds under `templates/vault/<path>`, mirroring
  `local/<path>`, rendered once by setup. `tests/` moved to `scripts/tests/`.
  A personal spike and thirty implementation plans that had shipped in every
  archive since v1.10.0 are back in the vault. `scripts/checks/check-tree-purity.sh`
  holds the tracked tree and the `.gitignore` root allowlist to the framework
  list, in doctor and pre-commit.
- Session-start reading list points at `local/learnings/patterns.md` and
  `local/learnings/troubleshooting.md` (the real ones) instead of the public
  placeholders.
- **graphify writes to `~/.agentBrain/workspace/derived/graphify/`** instead of
  `local/graphify-out/`. An existing output directory is moved there once, on
  install or first run. `uninstall` now moves the output aside instead of
  `rm -rf` on it.
- **`check-nda`** names a space by an opaque handle from its `space-id` and
  masks every printed path against all markers; it no longer prints the owner
  name through the path or the slug heading. Test-fixture passports
  (`__name__`) are not marker sources.
- **Vault hooks are versioned**: `scripts/hooks/vault-pre-commit.sh` is now the
  four-layer gate (note ids, plaintext secrets, NDA ratchet, intake) and
  `vault-post-commit.sh` sits beside it. `sync-agentbrain-local.sh` installs
  both into the directory `core.hooksPath` names. A fresh install used to get
  a one-layer hook.
- scripts/reports/, scripts/hooks/, scripts/sync/, scripts/tests/ added;
  flow scripts moved to scripts/flow/ with the launchd plist template path
  updated (job reloaded and verified via kickstart).
- **Installer**: one unified flow for every OS. The Darwin fork
  (bootstrap-macos.sh vs setup.sh) is replaced by a symmetric
  `bootstrap-<os>` dispatch via platform.sh (`bootstrap-macos.sh` +
  new `bootstrap-linux.sh`, same 4-step contract: tools -> brain -> pi ->
  doctor; WSL2 rides the linux route, `platform_flavor` prints the flavor).
  setup.sh now offers Pi configuration and the AGENTBRAIN_SETUP_PHASE doctor
  summary on every platform (configure-pi's macOS-only pieces self-guard).
  bootstrap-macos.sh journals the same steps and stays as the mac entry.
- **Installer unit version 0.2.0**: optional devtools step
  (`setup-devtools.sh`: mail / container / python intents via cascaded
  capability offers), `installer/VERSION` as the installer unit's source of
  truth (`AB_INSTALLER_VERSION` overrides).
- **Flow journal** (`scripts/installer/flow.sh`): the orchestrator journals
  every step/subflow with rc (which flow, which step, which subflow, from
  where, to where) to a run journal under /tmp.
- new-note.sh: `time` (HH:MM:SS UTC) added for task/session notes
  (loop-records); other types stay date-only.
- capability-install.sh moved to `scripts/lib/` (sourceable lib, never run);
  all consumers updated.

### Fixed

- The UUID5 namespace backup in the vault is write-once: setup and fix.sh create it when absent and refuse to overwrite it on a mismatch, which is the event it exists to expose.

- `setup-local-vault.sh` named `ensure_workspace` in its EXIT trap before the function was defined; a second run on an existing install (the link already there) exited early and failed with "command not found". Found by the sandbox validation of the GitHub publish.

- `check-em-dash --staged` counted every modified line that already carried a dash as new prose; it now refuses only when a change adds more dash lines to a file than it removes, so a mechanical rename across the docs no longer trips it.

- Graphify tests no longer depend on an LLM or on scanning a directory that Graphify
  intentionally excludes.
- Brain Explain tests are isolated from existing local configuration and MOC content.
- Incognito and local add-on manifest health checks now describe their actual runtimes.
- YouTube filename sanitization removes decomposed punctuation such as ellipses.
- **Agent detection**: an agent is now marked installed only when its CLI exists
  and its `--version` probe succeeds. A stale PATH shim or config directory can no
  longer make a clean machine report Claude Code, Pi or another client as installed.
- **Prerequisite flow**: pnpm is installed through the user-scoped Node/npm setup
  before the optional ABH profile integration runs.
- **Installer source integrity**: LAN-served bundles now carry an expected
  version and the canonical installer refuses stale bundles instead of silently
  installing an older checkout.
- **Website/LAN parity**: the maintainer LAN wrapper now serves the same
  canonical installer flow as the website, with only the source transport
  overridden for pre-publication acceptance testing.
- **Canonical root resolution**: skill-relation checks and Pi configuration now
  resolve the active agentBrain checkout through `AGENTBRAIN_DIR`,
  `AGENTBRAIN_HOME/agentBrain`, and the developer fallback instead of assuming a
  valid `~/agentBrain` symlink.
- **Agent detection**: a config directory no longer counts as an installed
  Claude Code client; the CLI and a successful version probe are required.
- **Diagnostics**: Pi skill links are counted correctly across nested skill
  directories, and stale-root failures are reported without an unbound-array crash.
- **Skill-link detection**: Claude Code, Copilot CLI and Pi are now considered
  installed only when their CLI exists and `--version` succeeds; stale config
  directories no longer force skill-link checks on clean machines.
- **Canonical Pi wiring**: the link checker and Pi configuration use the active
  agentBrain checkout instead of treating a plain `~/agentBrain` directory as the
  source of truth.
- **Agent skill wiring**: skill-link checks now require a real client CLI and successful version probe, and hermetic add-on tests use isolated client stubs so host-installed tools cannot contaminate results.
- **Canonical root**: skills are wired only into detected clients and resolve their source from the active agentBrain checkout.
- **Pi skill-link detection**: a globally installed Pi CLI no longer makes a clean sandbox require Pi skill links before Pi has been configured.
- **ABH profile idempotency**: rerunning the integration setup now rewrites only
  its managed provider patch, removing duplicate loader entries while preserving
  unrelated user-owned profile configuration.
- **Pi stale extensions**: Pi configuration removes brain-owned extension links
  whose canonical source no longer exists, preventing old private dependencies
  such as removed add-on modules from breaking startup.
- **ABH loader identity**: integration provider rows now use unique managed IDs, avoiding collisions with package-owned loader entries while keeping agentBrain the canonical source.
- **Autostart validation**: the user-level service uses the resolved `abh` binary and avoids the SC2015 shell ambiguity.
- **TTY-safe installer execution**: website, LAN and SSH/CI runs now distinguish a usable controlling terminal from a present but unusable `/dev/tty`, preventing partial setup and terminal-device errors.
- **Optional tool menu redraw**: compact version labels prevent long ABH/npm status text from wrapping, so Space toggles redraw the highlighted row instead of duplicating visible lines. Other CLI version labels are normalized and capped for terminal-safe output.
- **Agent menu redraw**: the optional tool selector now clears and redraws from the terminal origin instead of relying on cursor-up row counts, preventing duplicate rows on narrow terminals and after Space toggles.
- **macOS bootstrap flow**: the bootstrap now suppresses setup.sh's optional Pi pass and runs the dedicated Pi configuration once, removing duplicate Pi output and duplicate wiring work.
- **Post-setup copy**: the Next section now exposes `brain harness web` and optional autostart when ABH is available.
- **Prerequisite and bootstrap copy**: the installer now describes recommended tools as offers, and the macOS bootstrap no longer prints a misleading duplicate Pi-deferred step.
- **ABH peer dependencies**: the profile setup installs the provider peer set explicitly, reducing avoidable pnpm peer warnings during integration.
- **ABH peer-noise**: provider setup now pins only the three integration providers to the detected harness prerelease family. It no longer installs plain peer packages that create additional non-actionable `no abh.bundle` warnings.
- **Pi setup copy**: credential warnings no longer include shell commands that could expose API keys in history.
- **ABH setup readiness**: an installed agentBrain Harness now has its built-in base context, memory and skill providers verified automatically, without a redundant manual integration prompt. Older harness builds receive a compatibility mount only when needed.
- **ABH duplicate prevention**: managed compatibility state is cleared before base-provider detection, preventing duplicate loader entries after repeated setup runs.
- **Installer automation**: `AGENTBRAIN_ASSUME_YES=1` now bypasses the top-level install and guided/quick prompts instead of waiting on `/dev/tty`, so monitored clean installs cannot hang before bootstrap.
- **Inline prompt rendering**: shared installer menus now render below the existing installer screen and redraw only their own rows; they no longer clear the logo, scan or step context. Enter handles both CR and LF reliably.
- **Prompt rendering and Enter handling**: interactive menus now keep the installer context visible instead of clearing the screen, read CR/LF Enter reliably, and decode complete arrow events without leaking escape characters.
- **Standalone helper guard**: the embedded prompt helper no longer interprets the installer itself as `prompt-helper.sh` and exits with its CLI usage message.
- **TTY safety**: the installer now refuses to continue when no controlling terminal is available unless explicit automation mode is enabled; it no longer silently accepts the install default.
- **Prompt timeout handling**: a no-input timeout is no longer interpreted as Enter, so interactive installer confirmations wait for an actual user choice instead of advancing to personalization.
- **Single-frame prompt rendering**: interactive menus render their block exactly once below the installer output and repaint only that block while the cursor moves; no more duplicated question lines above the menu.
- **Stable prompt block**: menus redraw strictly in place with a fixed line count, wait indefinitely for a real keypress instead of redrawing on a timer, and no longer duplicate the question line above the menu. Direct keys 1/2 work in confirmations.
- **set -e safety in prompts**: conditional assignments in the shared prompt helper no longer abort the menu under `set -euo pipefail`; choosing Yes (Enter or y) now reliably continues the installer.
- **Enter key regression**: the prompt key reader lost its NUL delimiter flag in an earlier rewrite, so a LF keypress returned an empty read that was misread as EOF, silently cancelling the install confirmation. The delimiter is restored; Enter works as CR and LF, and the root cause is now covered by tests.
- **Detected editors preselected**: the Editor multi-question now preselects the detected editor in the shared menu (previously the checkbox list ignored detection and showed empty boxes), and the "(detected)" label only appears when something was actually detected.
- **Capability offers on real machines**: two runtime bugs proven and fixed on a clean test Mac: (1) a narrow PATH (ssh wrappers, non-login shells) made `command -v brew` fail so offers wrongly reported "no install recipe"; the standard Homebrew locations are now probed and added to PATH. (2) The auto-run after accepting an offer could collide with brew's own interactive "proceed? [y/n]" prompt; accepted recipes now run with stdin from /dev/null so they always execute non-interactively. Verified end-to-end: uninstall Ollama → install flow → offer appears (vertical, No default) → accept → Ollama installed and detected.
- **Onboarding agenda gap**: the install wizard overwrote preference files wholesale, so the free-text questions it does not ask (infrastructure, projects location, shell prefs, visual style, build-vs-buy, extra identities) could never be asked by /onboard again. The wizard now writes "(fill in later: /onboard asks this)" markers for those, preserves free-text answers from earlier runs/agents on re-runs, and the onboard skill documents the post-wizard agenda explicitly.
- **Real answers always win**: when a preference file already holds a real answer, the wizard never replaces it with a "(fill in later)" placeholder; only genuinely missing lines get the marker. Merge logic extracted to its own function and unit-tested against the shipped wizard source.
- **Merge actually used**: the preference merge built the merged result but the file write still serialized the original list; `write_pref` now writes the merged lines (real answers win over placeholders, wizard answers win over nothing). Proven by unit tests run against the shipped function source.
- **Off-by-one in zero-based menus**: numeric direct-select returned the raw row index, but three callers treated it as 1-based: the secrets-helper maintenance menu (choosing reinstall did nothing), the developer-tools keep/update/skip menu (pressing 1 ran update), and the install/skip menu (pressing 1 skipped). All callers now interpret the index consistently; verified by PTY tests pressing 1/2/3 against every menu.
- **Doctor shellcheck detection**: the doctor now probes the standard Homebrew locations (/opt/homebrew/bin, /usr/local/bin) when shellcheck is not on PATH, so a doctor run over SSH or from a narrow-PATH wrapper still runs the full 68 checks instead of silently skipping shellcheck.
- installer: `bootstrap/linux.sh` never sourced `scripts/installer/flow.sh`
  (the macOS twin did), so `flow_begin` died with "command not found" under
  `set -euo pipefail` and the Linux/WSL bootstrap crashed right after the
  Step 1/2 banner (seen on v1.10.2-prerelease-70-2). Fix mirrors macos.sh:
  shellcheck source + `. "$SCRIPTS/installer/flow.sh"`; standalone runs stay
  no-op safe via the empty-journal guard.
- checks: `check-work-note-structure.sh` registered as pre-cutover advisory in
  check-doctor's EXEMPT list (the work-note contract ratchet still has 64
  blocking MUST-debts in the vault; wire it into doctor after
  `scripts/retrofit-work-notes.sh` clears them per note).
- checks: doctor's shellcheck gate now runs with `-x` so `source=` directives
  are actually followed and the sourced libs are analyzed in context; all
  directives made root-relative (addons.sh, check-addons.sh,
  tools/install-prerequisites.sh, setup/setup-skills.sh,
  setup/setup-devtools.sh) and nine `A && B || C` patterns rewritten as real
  if/else (migrate-v2.sh, test-brain-update.sh, test-capability-install.sh,
  test-security-defaults.sh). Supersedes the earlier disable=SC1091
  workaround.
- release: all six `scripts/release/*.sh` resolve their ROOT via `realpath
  ${BASH_SOURCE[0]}` (house style, symlink-proof): invoking them through the
  root-level compat symlinks (e.g. `bash scripts/release.sh`) previously
  climbed one directory too far and looked for VERSION in $HOME.
- loop: `flow/loop-tick.sh` called `capture-findings.sh` next to itself
  (`scripts/flow/`) while it lives at the scripts/-root: every tick's
  detector step failed silently. Fixed the path; the root entry stays
  canonical (README, tools.md, launchd unchanged).
- tests: `test-loop-tick.sh` died silently with exit 127 (missing
  `scripts/flow/` in the fixture + `set -e` eating the failure before the
  asserts). Fixture now mirrors the production layout (scripts/checks/ with
  the root symlink, scripts/reports/) and reports through its assertions.
- The em-dash gate in `.githooks/commit-msg` was appended below the script's
  last `exit` and never ran for any message. Now placed before the first exit,
  with a test that executes the hook and observes it refuse.
- `test-active-space` backed up and faithfully restored its own leftover
  marker; `__astest__` sat in `local/.active-space` for weeks.
- `check-nda` printed the names it exists to withhold, via paths and the
  space slug heading.
- **Installer unit 0.2.1**: `install-agent-clis.sh`, `release/channel.sh` and
  `sync/move-agentbrain.sh` sourced `installer/prompt-helper.sh` relative to their
  own subdirectory instead of `scripts/`, so the "Agent CLIs and tools" step and
  the wizard's channel selection failed on a fresh machine with
  `No such file or directory`. Scripts in a subdirectory of `scripts/` now climb
  `/..` before resolving shared helpers.

## [v1.10.1] - 2026-08-15

### Fixed

- **pi-cloak: seed a default `cloak.json` during Pi configuration** — a fresh
  install shipped no `cloak.json`, so the pi-cloak extension warned "config not
  found" on every Pi session start. `configure-pi.sh` now copies a default
  `cloak.json` (enabled, empty patterns) on first install and never overwrites it on
  update. The always-on bash secret safety net runs regardless of the config;
  `cloak.json` only adds optional user-defined file-read patterns.

## [v1.10.0] - 2026-08-14

### Added

- **Addon attribution**: a required `author:` manifest field (lowercase handle).
  `addons.sh status`/`search` show an AUTHOR column and `registry-index.sh` stamps
  it into the published index, so every addon — first-party or adopted — is credited
  to its real author. The default is the vault **maintainer**, read from `brain.json`
  (seeded from the git identity at setup) and used to seed `addons.sh new` — never
  hardcoded.
- **Addon manifest schema — `license:` and `requires:`**: optional SPDX `license:`
  (absent = the framework default `Apache-2.0`, applied at index time) and
  `requires:` (space/comma-separated addon ids an addon depends on). `check-addons`
  validates both, `addons.sh check` warns when a required addon isn't enabled, and
  `registry-index` emits them. Per-addon manifest⇄CHANGELOG version parity is now
  enforced too (the ksc SemVer + Keep-a-Changelog invariant at the addon level).
- **Capability provisioning (`runtime_requires:`)**: one shared
  declare→detect→offer-install path for external runtime prerequisites, replacing
  four ad-hoc mechanisms. `platform_has` gains `ollama`/`uv`/`devbox`/`obsidian`/
  `open-webui` probes plus a `platform_capabilities()` enumerator; a new
  `scripts/capability-install.sh` provides `offer_install` (opt-in; package-manager
  auto-run, services / pipe-to-shell / `sudo` shown-only). Addons declare
  `runtime_requires:`; `check-addons` validates the tokens, `addons.sh check` warns
  when a runtime is missing, and enabling an addon offers to install it. `setup.sh`'s
  Obsidian install now flows through the same helper (graceful degradation).
  weekly-review + graphify declare `runtime_requires: ollama`. The full
  catalog/`ensure`-lifecycle is deferred until ≥5 capabilities earn it.
- **Doctor guard: session-start update-check must stay quiet** — a new
  `check-session-update-quiet` (doctor-wired) asserts that `brain-update --session`
  never routes progress to stdout (which the session hook injects, leaking a
  private/LAN origin URL) and never hangs on an unreachable origin.

### Fixed

- **`sync-agentbrain-local.sh` gains `--help` / `--dry-run`** (and rejects unknown
  options) — the committed CLI-safety test expected this behaviour; the script now
  ships it. **`check-local-content`** also exempts `local/skills/*/templates` and
  `local/tools` (skill payloads + tool-prototype workspaces, not curated notes).
- **Registry install: false `sha256 mismatch` when the index carries `author`**:
  adding the `author` field to the registry index made `addons.sh`'s 6-variable TSV
  read slurp the trailing author into the sha256 value, so every
  `addons.sh install`/`update` from a registry failed with a bogus mismatch. The
  read now consumes all 7 fields (author discarded). (`test-addons` — skipped by
  `doctor --fast` — was already catching this; the full doctor now runs clean.)
- **Installer: update an existing checkout from the public source, not its old
  origin**: `install.sh`'s "update existing checkout" step fetched from the
  checkout's own `origin` — which, on a checkout first cloned from a private/LAN
  Gitea, is an unreachable LAN URL (the install died with `unable to connect to
  <lan-ip>`). It now fetches from the installer's `$REPO` (the public repo),
  hard-resets to it (the public repo is a rewriting clean snapshot — unrelated
  lineage, so ff-merge cannot apply), and re-points `origin` to the public source
  so later updates track it too. `local/` is gitignored and never touched.
- **Session-start update-check must never surface a private origin or hang**:
  `brain-update --session` routed its "fetching <remote> …" progress line to
  stdout, which the session-start hook injects into the agent context — exposing a
  private/LAN `origin` URL and, on an unreachable remote, an 8s hang + timeout
  message. Progress now goes to stderr, and an automated session check uses a
  tighter budget and fails **silently** (exit 0, no output) when the origin is
  unreachable. A checkout whose `origin` is a private remote no longer shows a LAN
  URL or stalls at session start.
- **Public-parity guard against version-jump gaps**: every canonical release
  tag (vX.Y.Z ≥ v1.6.0) must exist on the public GitHub repo.
  check-release-published now compares dev tags against the public channel —
  advisory warning in the doctor (a freshly cut tag is legitimately
  unpublished for minutes), hard verify (PARITY_STRICT=1) at the end of
  every GitHub publish. Found and fixed the real case: v1.7.0 was tagged
  2026-08-02 but never published; backfilled as a clean snapshot + Release.
- The GitHub publisher now creates the Release object (changelog notes +
  archive asset, `--latest`/`--prerelease` aware) alongside the snapshot and
  tag — a tag alone left the public Releases page presenting an old version
  as "Latest". v1.8.0 and v1.9.0 were backfilled by hand.

## [v1.9.0] - 2026-08-10

The brain CLI release. One entry point (`brain`, alias `agentbrain`) for the
whole day-2 life — update, channel, wire, doctor, onboard, addons, sandbox,
uninstall — plus profile-first onboarding (13 questions → 5 interactions) and
a real browser sandbox that already caught its first bugs before shipping.
Verified on macOS live, Debian/Alpine containers, and headless over ssh.

### Added

- **`/space-docs` skill** (`system/skills/space-docs/`): produce a
  self-contained, transferable docs bundle (README + ARCHITECTURE + ROADMAP +
  MEMORY + rendered diagrams) with a deterministic `validate.sh` boundary /
  privacy / relevance gate — fails on machine-local paths, private/vault refs,
  dead / absolute / `..`-escaping links, secret material (keys/tokens),
  off-space deny-list terms (other clients), and any subfolder without a
  README; warns on internal hosts and credential-like values. 11-assertion test
  suite; executable by a cheaper model. Scaffold templates + guidance included.
- **`/brain-architect` skill promoted to `system/skills/`** (from private
  `local/skills/`, 2x-rule satisfied): evidence-gated architecture analysis
  executable by a cheaper model. Five-phase workflow (recon → building blocks
  → six constraint lenses → decision records → open-questions ledger), five
  fill-in templates with fixed language-neutral tokens, and a deterministic
  `validate.sh` form-checker (bash 3.2, 17-assertion test suite). Flags:
  `--lang en|nl`, `--html` (renders via brain-explain), `--peer-review`.
- **`system/versioning.md`**: the ksc policy (SemVer + Keep a Changelog +
  Conventional Commits) as a public framework doc, including the manual
  post-promote checklist that `/promote` deliberately does not automate,
  and the release cadence rule (assemble, do not stream).
- **`scripts/check-ksc.sh` in doctor**: enforces Keep-a-Changelog structure
  (`[Unreleased]` present), the policy doc's existence, and warns on
  non-Conventional commit subjects in recent history. The `/promote`
  aftercare checklist now ends with `doctor --summary` as proof of a
  complete promote.
- **`brain` is now the full agentBrain CLI** (also installed as the
  `agentbrain` alias): `update`, `channel`, `wire`, `doctor`, `onboard` and
  `addons` join `status`/`use`/`version` as subcommands that proxy the
  standalone `scripts/*.sh`. New primitive `brain wire [--skills|--pi]
  [--quiet]` is THE single wiring implementation (skills into every detected
  agent + the Pi deep integration) — setup's Pi step and brain-update's
  rewire now call it instead of duplicating the guards.
- **Profile-first onboarding** (13 questions → 5 interactions): the wizard
  opens with "What describes you best?" (profiles in choices.json preselect
  tech answers), shows ONE review screen (detection + profile as checkboxes:
  OS via uname, editor probed on PATH/Applications, languages/hosts scanned
  from ~/Developer and git remotes), then asks only the questions that change
  agent behaviour — language (default from the OS locale), autonomy (askFirst
  merged in, both lines still written), and updates (real channel names with
  the apply-mode riding along; `custom` sets channel and apply-mode
  separately). Source hierarchy per review row: detected > profile >
  "(fill in later)". "no profile" walks the full flow; AB_WIZARD_DEFAULTS
  behaves exactly as before. verbosity/design/decision write their defaults
  marked "(default — refine via /onboard)".
- **Devices & services onboarding** (/onboard Step 8 "Your world"): agent-led
  intake of machines and external services into `local/devices/` (with an
  index hop-page, hostnames canonical) and `local/integrations/`, from two
  new generic templates (`system/templates/device-template.md`,
  `integration-template.md`). Privacy rule embedded: credentials by
  helper/env/keychain NAME, never by value. Every onboarding run now closes
  by teaching the capture loops (/save-learning, /capture-tool-info, …).
- **Writing standard codified (Elements of Style)**: `system/writing-style.md`
  is the policy for every human-facing sentence (name the subject, omit
  needless words, concrete over vague, honest claims only), guarded by
  `check-writing-style.sh` in the doctor (doc must exist; needless-word and
  unnamed-subject scans warn on the user-facing scripts). Claude Code gets
  the `elements-of-style` plugin skill; other agents follow the doc. Mirrors
  the ksc pattern: policy doc + doctor check.
- **Install sandbox** (`scripts/installer/sandbox.sh`): a disposable
  install-testbed in the browser — a real terminal (ttyd) where every
  connection spawns a fresh non-root Debian container, so the real installer
  and wizard can be walked by a human on a brand-new machine; wrapper page
  with a reset button, carrying the landing-page identity (Satoshi +
  JetBrains Mono, oklch tokens, the animated neural logo) and a responsive,
  iOS-safe layout (100dvh). Network-aware like dropeye: reachable over LAN
  and tailnet (the page follows the host you visited), QR access in
  `status` (qrencode), an optional basic-auth gate (AB_SANDBOX_AUTH), and
  a macOS-firewall self-diagnosis hint on start. Composes with
  serve-lan.sh. Found its first real bug (missing npm on fresh Linux)
  within minutes of existing.
- **`brain uninstall`**: the symmetric uninstall (existing uninstall.sh —
  removes exactly what setup added, knowledge untouched, checkout deletion
  only via explicit --delete-checkout) joins the CLI.
- **Interactive CLI flows**: bare `brain` on a terminal opens a small menu of
  the day-2 tasks (scripted use still gets `status`); bare `brain channel` is
  a guided flow — status first, then the onboarding question with the option
  texts from choices.json, Enter keeps the current channel; and the wizard's
  multi questions (editor, languages, hosting) are checkbox pickers — arrows
  move, space (or 1-9) toggles, enter confirms — with automatic fallback to
  the comma-separated numbers on dumb/non-interactive terminals
  (`AB_WIZARD_PLAIN=1` forces the plain input).

### Fixed

- Onboarding wizard reads answers from `/dev/tty` — the interactive mode hit
  EOF on its own heredoc and had never actually worked; only the defaults
  express path was exercised. Ctrl-D now selects the default instead of
  crashing, and option descriptions no longer carry a stray parenthesis.
- Setup confirm prompts reject escape sequences (a stray arrow key no longer
  counts as an answer) and prompt on `/dev/tty` under `curl | bash`.
- `brain` invoked via its `~/bin` symlink no longer crashes on sourcing
  `lib/_toolpaths.sh` (and `brain version` shows the real git-describe): the
  script resolved its lib and repo relative to the symlink instead of the
  checkout.
- `channel set edge` in tag-mode auto-flips the mode to `branch` (edge tracks
  a branch, not a tag) instead of leaving a config that `brain update` must
  reject.
- Dependencies are now offered on every supported platform, not assumed:
  setup detects missing recommended tools (nvm/Node LTS, bun, uv) right
  after the preflight and offers the platform-aware installer (one consent,
  then unattended; brew parts skip themselves off-macOS) — previously the
  preflight pointed Linux users at a script only the macOS bootstrap ran.
  Safety nets in the agent-CLI menu: npm rows without Node offer nvm once;
  VS Code extension rows without the `code` CLI skip honestly (editors are
  deliberately not installed by agentBrain).
- `brain update` on an already-current install says so with evidence — the
  up-to-date line carries the git-describe version, not just a short sha —
  and `brain wire --quiet` keeps each failing part's real output in a log
  file instead of discarding it to /dev/null (a transient Pi-rewire failure
  during an update was undiagnosable).
- `brain status` on a single-checkout (consumer) install no longer shows the
  maintainer dev/live comparison ("dev: vunknown … run deploy-dev-to-live" on
  a machine without a dev checkout); it shows the checkout, the git-describe
  version and the update channel instead.

### Changed

- The personalize wizard is the closing step of setup — after Configure Pi and
  the daily loop — so technical output never interrupts the human questions.
- Onboarding intake is enum-first: OS, editor, languages/frameworks (incl.
  Lit) and code hosting are fixed choices with the detected value as default,
  `multi` fields accept comma-separated picks, and every list carries a
  `custom` escape — you can always type your own answer.
- The review screen carries a visible "add your own" row (a fresh machine
  has no scan hits, so the profile view is easily incomplete — Gitea, Azure
  DevOps); typed additions route to hosting or languages automatically, and
  Azure DevOps joined the fixed hosting options.
- Editor is a multi-pick too (VS Code + Neovim is a normal answer), and the
  release-channel question speaks first-timer language: "How eagerly do you
  want updates?" with per-option guidance instead of git jargon
  ("untagged main") and insider framing ("second machines, clients").
- The installer is honest about an existing checkout ("Update the existing
  agentBrain at …?" instead of "Install into …?"), and declining it offers to
  run only the personalization wizard — the usual reason to re-run the curl
  on an already-installed machine — before cancelling.
- Setup offers to install Obsidian (opt-in, N default) where it previously
  only printed a hint — the brain is a ready-made Obsidian vault, so the
  human viewer belongs in setup. Per platform: brew cask on macOS,
  flatpak/snap on Linux; WSL gets the winget hint plus the \\wsl$ vault
  path (GUI apps live on the Windows side). Editors stay out deliberately:
  they serve your code, not the brain.

## [v1.8.0] - 2026-08-07

The onboarding & first-run overhaul. Driven by a 16-persona gap analysis and
verified live on a clean Mac: one curl command now runs animation → honest
machine scan → guided install → identity → agent wiring → a doctor that ends
green, with `/onboard` as the single remaining step.

### Added

- **Engaging first-run installer** (vendored at `scripts/installer/`): brain
  point-cloud animation, honest machine scan, guided/quick mode with one-line
  what+why per step, vertical numbered menus with per-option hints, version
  display (git-describe), and a fresh login shell at the end so `pi` works
  immediately. `serve-lan.sh` rebuilds bundle + installer for LAN dev installs.
- **Prerequisites preflight** (`check-prerequisites.sh`): presence + minimum
  version floors, OS-gated. Xcode CLT / git / python3 / jq gate the install;
  Homebrew auto-installs on macOS; bun/uv install latest with guarded floors;
  per-tool keep/update/skip; Brewfile gains `shellcheck` and `yq`.
- **Onboarding completeness signal**: `check-onboarding.sh` + doctor check +
  end-of-setup warning; reports *pending* (not a red X) during initial setup.
- **/onboard intake v2**: canonical fixed-choice schema (`choices.json`) with a
  description per option; the language question is asked in English with each
  option described in its own language; `artifactLanguage` replaces the unclear
  "Mixed"; UI-locale is derived from the language answer (no duplicate question).
- **Identity**: seed template + `/onboard` step; git identity is guaranteed at
  install time (name/email asked when the config is empty — the vault autosync
  commits from day one).
- **MCP registration for Pi, Gemini and Kiro**: enabling `agentbrain-mcp` now
  actually wires `brain_search` into those agents' configs.
- **secrets-helper recommended on macOS** during onboarding (Keychain over plain
  `auth.json`/`.env`); the Pi keychain warning is now actionable.
- **Model-free onboarding wizard** (`scripts/onboard-wizard.sh`, optional setup
  step): the fixed-choice intake as terminal menus — core onboarding completes
  during install, no AI provider needed; `/onboard` deepens later (skip-if-done).
  `AB_WIZARD_DEFAULTS=1` = scripted express mode.
- **Agent-CLI smoke tests** after `npm install -g` — npm exit 0 is not an install.
- **ksc release tooling**: `changelog-draft.sh` (Conventional Commits → Keep a
  Changelog draft), a release guard refusing an undocumented release, and
  git-describe based version display everywhere; `commit-msg` hook enforces
  Conventional Commits.
- New doctor guards: `check-symlinks` (tracked symlinks must be relative and
  resolve), plus schema/identity/prereq test suites.
- Skills: lottie-animator addon + LottieFiles motion-design references,
  impeccable v4.0.4 vendored, namecheck trademark clearance step.

### Fixed

- **Fresh-machine hardening (whole classes, verified on a clean Mac):**
  shared `scripts/lib/_toolpaths.sh` gives every probing script honest tool
  detection (brew prefix, nvm, bun, `~/.local/bin`); PATH persisted shell-aware
  (bun rc lines, brew shellenv, brain-CLI bin dir); installer scan loads nvm.
- **Silent-death class**: PyYAML absence soft-skips visibly; `check-links`
  reports broken symlinks instead of crashing; missing skill-relation targets
  warn instead of fail; the spaces-extract test skips visibly without `yq`.
- **Portability**: stock bash 3.2 empty-array expansion (brain-restore);
  hoisted-vs-nested npm module resolution for the Pi tsconfig (incl. typeRoots);
  four absolute tracked symlinks became relative.
- **Update safety**: 8-second watchdog on the update fetch — an unreachable
  origin can no longer hang session start.
- Public GitHub publish pushes the release tag along with the snapshot, so
  channel resolution works on installs cloned from GitHub.
- `channel.sh` resolves the repo through the `~/agentBrain` alias (symlink or
  dir) — fresh machines no longer fall back to a dev-only path.
- `configure-pi` loads tool paths via the shared lib — `nvm use` under `set -u`
  died on an unbound variable inside nvm.
- Event bus no longer defaults the emitting agent to `claude`; unset now warns.
- secrets-helper install trusts its tap (brew 6.x refuses untrusted taps).

### Changed

- Superpowers plans/specs documented (onboarding overhaul, /architect skill)
  with README coverage; intentional shellcheck idioms annotated throughout.

## [v1.7.0] - 2026-08-02

Consolidation + hardening release. On top of the usage/cache observability,
transcript digests feeding the retro/insights loop, and addon changelog
governance that opened the cycle, this release lands the queue+dispatch
component, the unified explainer index, the sealed-spaces workflow, a
project-wide SPDX/licensing sweep, and a privacy-hygiene pass over the public
layer. Feature + hardening since v1.6.3.

### Added

- **Queue + dispatch component** — a markdown-native work queue (`type: task`
  notes under `local/queue/<scope>/`) with `scripts/queue.sh`
  (add/start/done/cancel/dispatch/board), event-bus dispatch, and a `/queue`
  skill. History + status live in frontmatter.
- **`/explain-branch` skill** — generate a themed HTML explainer of a branch's
  commits plus a merge/landing strategy, via brain-explain.
- **Unified explainer index** (`scripts/reports/build-explainer-index.py`) — one
  browsable page across sources: collapsible source→category tree, search with
  highlight, spaces toggle, deep-dive/explainer kind badge, config-driven
  language label (`system/explainers/locales.json`), and co-located `preview.png`
  thumbnails. Missing pages are rendered on build.
- **Ecosystem map** (`scripts/reports/build-ecosystem-index.py`) — a searchable index of
  every project (domain→status→project, active/pending/vendored badges,
  copy-path), driven by `local/ecosystem/projects.json`.
- **`new-space.sh`** — scaffold a sealed space paspoort (fresh `space-id` +
  path-derived `id`), with `test-new-space.sh` wired into doctor. Closes the gap
  where spaces had no create command (`new-note space` now redirects to it).
- **`docs/spaces.md`** — one canonical spaces workflow (create → route → map →
  seal → deliver), replacing the previously scattered, partly-stale coverage.
- **Opt-in auto-push git hook** (`.githooks/post-commit`), gated by
  `git config agentbrain.autopush true` — tracked but a silent no-op by default,
  so clones never inherit auto-push. A `[skip-push]` marker (or
  `COMMIT_SKIP_PUSH=1`) opts a single commit out of the push.
- **Verified `goal` command for Pi**, with usage accounting that counts nested
  goal-evaluator calls.
- **Prompt-cache observability** — usage reports now include Claude prompt-cache
  reuse and cache-read/creation figures.
- **`session-digest`** — extract and aggregate Claude Code + Pi transcripts;
  wired into `brain-insights` (audit questions) and `brain-retro` (skills audit
  with digest usage evidence).
- **Model-routing subagents for Claude Code** (executor / scout) in agent-config.
- **Nested owned-space repos** are pushed alongside the personal vault by the
  sync flow.
- **brain-explain**: auto-open the rendered explainer in the browser
  (`--no-open` / `BRAIN_EXPLAIN_NO_OPEN` opt-out) and double-click lightbox for
  mermaid diagrams.
- **web-interface-guidelines** addon-skill; addon skill-wiring documented.
- **doctor**: lint for volatile prompt-prefix placeholders.
- **hallmark + security-pipeline addons** — `hallmark` (anti-AI-slop frontend
  design skill for greenfield pages, audits, redesigns, and design extraction
  from URLs/screenshots) and `security-pipeline` (a Semgrep injection-sink
  template pack the public `p/ci` ruleset misses); both wired into the addon
  client-capability matrix (`clients.md`).
- **Nine skill definitions** — brain-explain, component-motion, cro-optimize,
  shorthand, technique-transplant, treasure-hunt, web-3d, weekly-review, and
  youtube-digest, plus their `skill-relations` wiring.
- **Copy-norms writing system** (STE-derived) — a controlled-language writing
  norm with sentence-length enforcement in `check-explainers`.
- **Conventional Commits enforcement** — a `commit-msg` git hook that rejects
  commit subjects which don't follow the Conventional Commits format.

### Changed

- **SPDX Apache-2.0 headers on all `.sh` files** — every tracked shell script now
  self-identifies its license, matching the project `LICENSE`.
- **brain-explain hardening** — the callout parser accepts both `:::name{title=}`
  and a trailing-title form; `clean-flat` is now the default theme; layer/card/flow
  blocks use vertical-only spacing.
- **Config-driven locale detection** — the dutch-dominant detector and explainer
  index both read stopwords from a shared `locales.json`, so doctor + promote
  gates and the language label stay in sync (agentBrain stays EN-primary).
- **Onboarding covers confidential spaces** — `/onboard` gains an optional Spaces
  step (and a `spaces` focus) explaining the sealing model and per-owner backup.
- **Maintainer docs**: `docs/development.md` documents the opt-in auto-push hook
  and the `[skip-push]` commit marker.
- **Addon changelog governance** — adopted Keep a Changelog + SemVer as the addon
  convention and backfilled `CHANGELOG.md` (+ PATCH bump) across the addons.
- **check-skill-relations** now recognizes addon-delivered skills (e.g. `uxray`)
  as valid, reciprocal relation targets, with name deduplication.
- **doctor** no longer flags vendored / third-party / fixture content — skill
  `references/`, dependency venvs, benchmark fixtures, and per-space `analyses/`
  bundles are exempt like the machine-generated content they are.
- Cache-aware LLM prompt-composition guideline added to agent-config/system docs;
  peer-review documents subagent-peers as a second review mechanism.

### Fixed

- **Privacy hygiene in the public layer** — dropped private client-project
  references and a personal path from public skills/addons (cro-optimize,
  treasure-hunt, security-pipeline, weekly-review); added the missing `queue/`
  and `explain-branch/` skill READMEs.
- **Spaces docs realigned to the context-inference model** — `tools.md`,
  `skills.md` and `architecture.md` no longer present the decommissioned
  `active-space` session mode as the routing mechanism; writes route per-write
  via `system/lib/context.sh`.
- **new-note**: guard against notes written outside `local/` (auto-prefix), so a
  path without the `local/` prefix no longer lands outside the vault with a
  silently mismatched UUID.
- **check-explainers**: strip HTML tags before the copy-scan (BEM `--` modifiers
  were false positives).
- **youtube-digest**: worker-pool `pLimit` no longer removes the wrong promise.
- **session-digest**: aggregate namespaced skill names correctly.

### Security

- **pi-cloak**: redact known-secret env values from bash output; tightened the
  bare-token-line rule to hex-only; fixed bash-secret redaction across the
  process boundary; fixed a UUID false positive.
- **check-agentbrain-local**: the URL-credential secret rule no longer
  false-positives on localhost dev URLs with an `@` in the path (which had
  blocked private-vault syncs on machine-generated network logs).

## [v1.6.3] - 2026-07-07

Consumer-layout fixes, found by installing v1.6.2 on a single-checkout Linux
host (Raspberry Pi): a plain `~/agentBrain` clone with `local/` as a regular
directory inside it, rather than the maintainer's dev/live symlink flip.

### Fixed

- **Space seal-breach detection now works on nested vault layouts.**
  `check-space-boundary.sh` grepped staged paths for `^spaces/`, but when
  `local/` is a plain directory inside the framework checkout, git resolves to
  the enclosing repo and force-added space paths are staged as
  `local/spaces/…` — the guard silently missed the breach (and
  `test-space-boundary.sh` proved it). The breach grep is now prefixed with
  `git rev-parse --show-prefix`, covering dedicated-vault, shared-symlink and
  nested layouts alike.
- **`brain update` resolves the repo on consumer installs.** `brain-update.sh`
  and `channel.sh` defaulted to the maintainer path
  `~/Developer/agentBrain-dev` when `~/agentBrain` is a real directory (not a
  symlink), so a stock install could not self-update ("not a git repo" /
  "channel resolved to nothing"). Both now use the alias itself when it is a
  git checkout.
- **`brain-extract` fails loud when `yq` is missing.** Call sites defaulted a
  failed `yq` to "", so a missing binary surfaced as the misleading
  "space index.md has no space-id". A hard dependency check up front now names
  the real problem.

## [v1.6.2] - 2026-07-07

Consolidates the 1.6.2 prerelease line (01-07, entries below) plus a final
round. Highlights of the line: per-write space context inference replacing the
leaky vault-global active-space marker, an agent-agnostic note-id commit gate,
the `/skills` lifecycle orchestrator, nvm-aware agent-CLI installs on Linux
hosts, and preferences surfaced in the agent consult instruction.

Final round on top of prerelease-07:

### Added

- **`/namecheck` skill** (`system/skills/namecheck/`): sweep a product name
  across npm (package + scope), GitHub user/org (+ defensive variants), Open
  VSX, VS Code Marketplace, Homebrew, common TLDs, X and Reddit — and for every
  TAKEN resource report what's actually behind it (description, owner, site
  title) so conflict risk can be judged, not just availability. Ships with its
  own VERSION/CHANGELOG and a conflict-judgment rubric.
- **War-game mission template** (`system/templates/war-game-mission-template.md`):
  reusable blueprint for wargaming a mission on paper (moves, forks, abort
  conditions) before feeding it to a cheaper executor model.

### Fixed

- **Hermes integration completes on bun-less hosts.** The `agentbrain-mcp`
  server dropped its only Bun-specific API (`Glob` → node's recursive
  `readdir`), so one code path now runs identically under bun and node/tsx
  (verified on both; 42 addon tests green). `setup-hermes.sh` keeps printing
  the MCP wiring hint until `agentbrain` actually appears in Hermes'
  `config.yaml` — previously the hint appeared only on first install, so a
  host with the SOUL.md pointer but no MCP entry was never nudged again — and
  the hint is runtime-detected (bun, else `npm install` + `npx tsx`).
  `system/agent-config/hermes.md` documents the node fallback and the known
  not-yet-integrated Hermes surfaces (memory providers, hooks).

### Changed

- **Repo-root hygiene**: `.gitignore` now allowlists the repo root and blocks
  force-added ignored paths.
- **Addon client matrix**: `agentbrain-mcp` declares `hermes: rules` support.

## [v1.6.2-prerelease-07] - 2026-07-06

### Added

- **Preferences now surfaced in the agent consult instruction.** The
  `agentbrain` Pi extension's session-start system prompt now tells the agent to
  consult `local/preferences/personal/` alongside the core memory files at the
  start of meaningful coding work, including a pointer to each preference's
  `Wanneer` section. Previously preferences were discoverable but not
  signposted, so agents only found them when already looking. This is the
  knowledge-level lever (no hook, no fork) that lets a preference such as the
  new `ponytail-coding-default` (default ponytail discipline on coding tasks,
  lift-off for greenfield build intent) be reliably noticed and applied with
  judgment rather than mechanically injected.

## [v1.6.2-prerelease-06] - 2026-07-05

### Changed

- **Layer-B "ask" policy for uncertain space context.** When path signals cannot
  resolve a space but the conversation is about a specific owner/client, agents now
  ASK which owner-space a note belongs to (enumerated at runtime from `local/spaces/*/`)
  instead of silently defaulting owner-work into the personal vault. Documented
  canonically in `system/rules.md` (Spaces / ownership), with pointers from the
  `save-learning` and `project-update` skills. The policy is owner-agnostic — no client
  names appear in any public file (`check-space-boundary` enforces this); the concrete
  spaces live only in the gitignored `local/spaces/<slug>/` passports.

## [v1.6.2-prerelease-05] - 2026-07-05

### Changed

- **Space recall migrated off the vault-global marker.** MCP recall
  (`agentbrain-mcp` `search.ts` `activeSpace()`) now resolves the active space from
  the per-session env only (`AGENTBRAIN_CONTEXT`, with `AGENTBRAIN_SPACE` as a
  back-compat alias) — the same signal the write side infers. The
  `local/.active-space` marker is read by nothing anymore, completing the
  decommission of the leaky vault-global state that could cross parallel sessions.
- **`active-space.sh` fully deprecated.** `use` / `show` / `clear` still round-trip
  for backward-compat, but a warning makes clear the marker has NO effect on writes
  or recall; set `AGENTBRAIN_CONTEXT=<slug>` for the session instead.

### Added

- **The space reverse-map auto-regenerates.** `infer_context()` rebuilds
  `local/.space-map.json` when it is missing or older than a space passport, so
  code-root routing stays correct without a manual `build-space-map.sh` run
  (best-effort; a partial checkout without the generator just skips it). The
  repo-root resolver is captured at source time so it survives an empty
  `BASH_SOURCE[0]` when called from a bare command line.

## [v1.6.2-prerelease-04] - 2026-07-05

### Added

- **Per-write space context inference** (`system/lib/context.sh` `infer_context()`
  + `scripts/build-space-map.sh`). `new-note.sh` now decides which space a note
  belongs to per-write, from PATH-based and explicit signals only — the CWD's
  code-root, `AGENTBRAIN_CONTEXT`, the git remote — never content (a shared
  tech-stack would false-positive). A note written from a client's repo
  auto-routes to that client's space; personal/framework work lands in the shared
  vault. `build-space-map.sh` generates the reverse-map (`local/.space-map.json`,
  gitignored, holds absolute paths) from the space passports. Covered by
  `scripts/test-context.sh` (10 cases, one per breakage scenario) registered in
  doctor.

### Changed

- **`new-note.sh` context routing replaces the global active-space marker**, which
  married work-context to storage and leaked across parallel sessions. Outcomes: a
  confident slug writes into that space, `ambiguous` refuses, and `unknown` falls
  back to the main vault — or refuses under `--strict` /
  `AGENTBRAIN_STRICT_CONTEXT=1`. Adds a `--context <slug>` alias of `--space`, and
  degrades gracefully to the main vault when `system/lib/context.sh` is absent.
- **`active-space.sh` write-role deprecated.** The `.active-space` marker no longer
  routes note WRITES (those infer context per-write); `use` warns and the marker
  survives only to scope MCP recall. `save-learning` documents the new routing, and
  `test-active-space.sh` now guards that the marker does not route writes.

## [v1.6.2-prerelease-03] - 2026-07-05

### Added

- **Agent-agnostic note-id commit gate** (`scripts/validate-staged-note-ids.sh`
  + `scripts/hooks/vault-pre-commit.sh`, installed into the vault repo's
  `.git/hooks/pre-commit` and self-healed on every `sync-agentbrain-local.sh`
  run). A note whose `id:` doesn't match `uuid5-gen.sh` for its path can no
  longer be committed — no matter which agent or tool wrote it, including a Bash
  heredoc that bypasses the per-agent Write/Edit hooks. This is the one
  enforcement layer that is both agent- and tool-agnostic; the per-agent hooks
  become fast feedback rather than the source of truth.

### Fixed

- **Pi's note-id validator now BLOCKS a bad id pre-write instead of only warning
  after the fact.** It previously fired on `tool_result` and merely logged to
  stderr, so a note written under Pi could land with a mismatched (or
  hand-fabricated) id that the Claude Code PostToolUse hook (exit 2) would later
  reject — an enforcement asymmetry that let one agent build what another rejects
  by design. `note-id-validator.ts` now also runs on `tool_call` and returns
  `{ block: true }` for a Write carrying a mismatched id (mirroring
  `incognito-guard` / `git-interceptor`), with the `tool_result` advisory kept as
  a net for Edit/MultiEdit.
- **`new-note.sh` no longer mints a wrong id for a project note passed as a
  directory.** Project notes live at `<dir>/index.md`; passing the dir path
  hashed the directory instead of `.../index`, yielding a valid-but-wrong UUID5.
  It now appends `/index` (with a transparent notice) so the computed id matches
  the real file path.
- **`new-note.sh` now scaffolds project notes with a default `status: active`.**
  A freshly scaffolded project previously landed without a `status:` field, which
  `check-project-status-enum` rejects — so the note failed doctor (and could block
  the pre-push gate) until a status was added by hand. Same scaffold-produces-an-
  invalid-note class as the `/index` fix above.

### Changed

- **`scripts/validate-note-id.sh` gained a `--content-file` mode** so a note's id
  can be validated before the file is written (its target dir need not exist
  yet); this backs the Pi pre-write block with zero formula drift. Covered by 3
  new cases in `scripts/test-validate-note-id.sh` (13 total).

## [v1.6.2-prerelease-02] - 2026-07-04

### Added

- **`/skills` — local skill-lifecycle orchestrator** (`system/skills/skills/`). A
  thin router over existing tooling: `list` / `sources` / `audit` / `sync`, plus an
  `add-repo` flow that delegates discovery to skill-finder, scaffolding to
  addon-create, and enable/disable to `addons.sh`. Anchors on the `~/agentBrain`
  alias so it resolves the brain root through the `local/` vault symlink. Promoted
  from `local/skills/` after end-to-end testing.

### Changed

- **`skills audit` is now a layered audit**, folding in the skill-auditor
  methodology: it checks SKILL.md instructions for prompt-injection and
  `allowed-tools` for permission wildcards — not just code — and uses precise code
  patterns that no longer false-positive on plain function expressions or a
  regex's `.exec` method call.

## [v1.6.2-prerelease-01] - 2026-07-04

### Fixed

- **Agent-CLI installer now honors the nvm-managed Node contract.**
  `install-agent-clis.sh` sourced no nvm and ran `npm install -g` against
  whatever `npm` was on PATH, so on a non-nvm host (system/apt Node on Linux
  or a Raspberry Pi) global installs targeted a root-only prefix
  (`/usr/lib/node_modules`) and died with EACCES — and the "run manually" hint
  just reproduced the failure. The installer now loads nvm before agent
  detection and the install loop, and guards each `npm install -g` against a
  non-writable global prefix, skipping with an actionable "use nvm-managed
  Node, never sudo" message instead of a wall of EACCES.

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
- CI workflow calls `bash scripts/checks/doctor.sh --ci` for full parity with local checks
- `CHANGELOG.md` following Keep a Changelog format

### Changed

- `brain.json` path field now uses `~` instead of absolute home directory path
- CI workflow uses single `doctor.sh --ci` command instead of duplicated check list

### Fixed

- Doctor check counter now correctly tracks passed/failed checks in all modes
- Compact default output (path-naming details only in `--verbose`)

## [v1.4] - 2026-05-18

### Added

- Doctor health audit system (`scripts/checks/doctor.sh`) with 10 automated checks
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
- CI workflow now calls `bash scripts/checks/doctor.sh --ci` for parity with local doctor
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
