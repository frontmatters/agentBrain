---
date: 2026-05-18
type: system
tags: [scripts, tooling, meta]
id: df325f9e-f6ff-5e0c-beed-4b44eb8e9fa4
---

# scripts

Tooling for agentBrain setup, validation, and maintenance.

## Scripts

The folder is organized by role; see "Installer script naming scheme" below
for the verb-first conventions.

| Locatie | Inhoud |
| --- | --- |
| `installer/` | de install-unit: orchestrator (`install.sh`), flow-journal, prompts, `bootstrap/{macos,linux}.sh`, dev-helpers, `VERSION` (0.2.0) |
| `lib/` | sourceable libs (sourced, nooit gerund): `platform.sh`, `capability-install.sh`, `skills.sh`, `_toolpaths.sh`, `_strings.sh`, ... |
| `setup/` | `setup.sh` + 23 component-subscripts — brain-onderhoud (dual-use: installer-stap én later zelf te draaien) |
| `tools/` | tool-installers: `install-prerequisites.sh`, `install-agent-clis.sh`, `install-lightpanda.sh` (+wrapper) |
| `checks/` | 52 state-gates: `check-*`, `doctor.sh`, `smoke-test.sh`, `audit-interactive.sh`, `validate-install.sh` |
| `tests/` | 38 behavior-suites: `test-*` |
| `hooks/` | 4 note-id/session hooks (git + Claude session) |
| `reports/` | build/report scripts: report-orphans, report-stale, render-findings-backlog, build-indexes/previews/maps |
| `sync/` | vault-sync familie: sync-agentbrain-local/shared/space, promote-to-shared, move-agentbrain, dev-sync-status |
| `release/` | 10 release/publish scripts: release, release-check, bump-version, channel, deploy-dev-to-live, publish-* , package-addon, mirror-registry |
| `scanman/` | 10 scanman-familie scripts |
| root (entries) | ±24 top-entries die agents/gebruikers rechtstreeks aanroepen: `brain.sh`, `addons.sh`, `queue.sh`, `new-note.sh`, `new-space.sh`, `new-addon.sh`, `uuid5-gen.sh`, `agentbrain-pointer.sh`, `migrate-v2.sh`, `configure-pi.sh`, `privacy-scan.sh`, `changes.sh`, `fix.sh`, `session-digest.sh`, `capture-findings.sh`, `changelog-draft.sh`, `ensure-daily-note.sh`, `update-daily-note.sh`, `update-startup-context.sh`, `active-space.sh`, `offboard.sh`, `import-offboard.sh`, `onboard-wizard.sh`, `uninstall.sh`, `move-agentbrain.sh`, `selftest*.sh`, `validate-note-id.sh`, + `.py` index-builders |

Compat-symlinks op root verwijzen naar verplaatste checks (fase 5 van de
installer-unit verwijdert die; zie scripts/installer/README.md).

## Installer script naming scheme

Sub-installers follow one verb-first scheme; stick to it when adding one:

| Pattern | Role | Examples |
|---|---|---|
| `installer/bootstrap/<os>.sh` | full machine bootstrap (tools + brain + agent); phase 3 merges this into one flow | `installer/bootstrap/macos.sh` |
| `setup.sh` / `setup-<component>.sh` | brain setup and per-component configuration | `setup.sh`, `setup-devtools.sh`, `setup-git-hooks.sh` |
| `install-<what>.sh` | brings in a tool or CLI | `install-prerequisites.sh`, `install-agent-clis.sh`, `install-lightpanda.sh` |
| `check-prerequisites.sh` | preflight presence/version report | `check-prerequisites.sh` |
| `lib/capability-install.sh` | sourceable LIB (never run directly): install/start/health arms per capability | sourced by `setup-devtools.sh`, `test-capability-install.sh` |
| `scripts/lib/*.sh` | other sourceable libraries | `_strings.sh`, `_toolpaths.sh` |

Rules: verb-first naming; sourceable libraries are sourced, never executed;
new optional tool bundles go through `setup-devtools.sh` intents + capability
arms (`capability-install.sh`), not as new standalone installers.

## Usage

```bash
# First time setup
bash scripts/setup/setup.sh

# Generate a UUID5 for a new note
bash scripts/uuid5-gen.sh "learnings/My-New-Note"

# Run full health audit
bash scripts/checks/doctor.sh

# Validate local structure only
bash scripts/checks/check-agentbrain-local.sh

# Type-check Pi extensions on machines bootstrapped for Pi
bash scripts/checks/check-pi-extension-types.sh

# Run Pi extension helper tests
bash scripts/tests/test-pi-extensions.sh
```

## Reconfigure reference

What to run when something changes — no need to re-run full setup.

| What changed | Command |
|---|---|
| **Vault location** (moved to a new path) | `bash scripts/sync/move-agentbrain.sh <new-path>` |
| **Locale / UI language** | `/config` (agentBrain skill) or `export AGENTBRAIN_LOCALE=nl` in shell rc |
| **Agent connections** (add/remove Claude, Copilot, Gemini…) | `bash scripts/setup/setup-agent-integrations.sh` |
| **Add-ons** (install, uninstall, enable, disable) | `bash scripts/addons.sh install <id>` / `bash scripts/addons.sh uninstall <id>` |
| **Pi agent** (update symlinks, skills, extensions) | `bash scripts/configure-pi.sh` |
| **Skills** (re-sync brain skills into agent dirs) | `bash scripts/setup/setup-skills.sh` |
| **Preferences** (personal, team, org) | `/onboard` (agentBrain skill) |
| **Hermes SOUL.md pointer** | `bash scripts/setup/setup-hermes.sh` |
| **Health audit + auto-repair** | `bash scripts/checks/doctor.sh --fix` |
| **Full uninstall** | `bash scripts/uninstall.sh` (add `--purge` to also wipe addon configs) |
