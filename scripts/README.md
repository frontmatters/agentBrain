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

| Location | Contents |
| --- | --- |
| `installer/` | installation entry points and platform bootstrap scripts |
| `lib/` | sourceable shell libraries |
| `setup/` | setup entry point and component scripts |
| `tools/` | optional tool installers |
| `checks/` | installed checks and `doctor.sh` (selection depends on the package) |
| `hooks/` | note-id and session hooks |
| `reports/` | report and index builders |
| `sync/` | vault, shared and space sync utilities |
| `scanman/` | repository analysis utilities |
| root (entries) | user-facing entry points such as `brain.sh`, `addons.sh`, `queue.sh`, `new-note.sh`, and `privacy-scan.sh` |

Source checkouts may also carry maintainer-only test suites and release tooling;
these are not guaranteed to be present in an installed archive.

Compat symlinks at the root point to relocated scripts, so older command lines
keep working.

Runtime shell scripts and the list-* skill entry points route vault reads and
writes through `scripts/lib/vault.sh`; paths under `vault/` in note ids remain
logical regardless of the physical vault location. `AGENTBRAIN_VAULT` takes
precedence over the checkout link. In a source checkout, `scripts/checks/check-vault-config.sh`
rejects checkout-derived vault paths in `.sh`, `.ts`, `.mjs` and `list-*`
runtime files; its negative case proves shell and TypeScript violations are
caught. Extensionless add-on and skill entry points resolve the vault through
the shared resolver. In a source checkout, the suites
`scripts/tests/test-vault-runtime-routing.sh` (representative readers and writers
against a throwaway external vault) and `scripts/tests/test-bins-use-vault-resolver.sh`
(the resolver contract) cover this; a release does not ship them.

## Installer script naming scheme

Sub-installers follow one verb-first scheme; stick to it when adding one:

| Pattern | Role | Examples |
|---|---|---|
| `installer/bootstrap/<os>.sh` | full machine bootstrap (tools + brain + agent) | `installer/bootstrap/macos.sh` |
| `setup.sh` / `setup-<component>.sh` | brain setup and per-component configuration | `setup.sh`, `setup-devtools.sh`, `setup-git-hooks.sh` |
| `install-<what>.sh` | brings in a tool or CLI | `install-prerequisites.sh`, `install-agent-clis.sh`, `install-lightpanda.sh` |
| `check-prerequisites.sh` | preflight presence/version report | `check-prerequisites.sh` |
| `lib/capability-install.sh` | sourceable LIB (never run directly): install/start/health arms per capability | sourced by `setup-devtools.sh` (and, in a source checkout, `scripts/tests/test-capability-install.sh`) |
| `privacy-scan.sh` | Public-content scan and hard gate against `.private` files/directories under `system/` (staged/tracked) | pre-commit + pre-push doctor; in a source checkout also `scripts/tests/test-private-skill-boundary.sh` |
| `scripts/lib/*.sh` | other sourceable libraries | `_strings.sh`, `_toolpaths.sh` |

Rules: verb-first naming; sourceable libraries are sourced, never executed;
new optional tool bundles go through `setup-devtools.sh` intents + capability
arms (`capability-install.sh`), not as new standalone installers.

## Usage

```bash
# First time setup
bash scripts/setup/setup.sh

# Generate a UUID5 for a new note
bash scripts/uuid5-gen.sh "vault/learnings/my-new-note"

# Check the health of your install and vault (= scripts/checks/doctor.sh --user)
brain doctor

# Validate the vault structure only
bash scripts/checks/check-vault-private.sh
```

## Reconfigure reference

What to run when something changes — no need to re-run full setup.

| What changed | Command |
|---|---|
| **Vault location** (moved to a new path) | `bash scripts/sync/move-agentbrain.sh <new-path>` (relinks CLI and add-on bin links pointing into the old checkout, without replacing unrelated files) |
| **Session-start CLI health** | `bash scripts/flow/update-startup-context.sh` reports broken checkout links and a missing `brain` command with repair commands; it does not repair them |
| **Locale / UI language** | `/config` (agentBrain skill) or `export AGENTBRAIN_LOCALE=nl` in shell rc |
| **Agent connections** (add/remove Claude, Copilot, Gemini…) | `bash scripts/setup/setup-agent-integrations.sh` |
| **Add-ons** (install, uninstall, enable, disable) | `bash scripts/addons.sh install <id>` / `bash scripts/addons.sh uninstall <id>` |
| **Pi agent** (update symlinks, skills, extensions) | `bash scripts/configure-pi.sh` |
| **Skills** (re-sync brain skills into agent dirs) | `bash scripts/setup/setup-skills.sh` |
| **Preferences** (personal, team, org) | `/onboard` (agentBrain skill) |
| **Stale client pointers** | `bash scripts/checks/check-installed-pointers.sh` to inspect; re-run the named `setup-<client>.sh` to refresh |
| **Hermes SOUL.md pointer** | `bash scripts/setup/setup-hermes.sh` |
| **Health audit + auto-repair** | `brain doctor --fix` |
| **Full uninstall** | `bash scripts/uninstall.sh` (add `--purge` to also wipe addon configs) |
