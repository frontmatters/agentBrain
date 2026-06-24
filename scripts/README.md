---
date: 2026-05-18
type: system
tags: [scripts, tooling, meta]
id: df325f9e-f6ff-5e0c-beed-4b44eb8e9fa4
---

# scripts

Tooling for agentBrain setup, validation, and maintenance.

## Scripts

| Script                          | Purpose                                                                                    |
| ------------------------------- | ------------------------------------------------------------------------------------------ |
| `setup.sh`                      | First-time setup: creates directories, installs agent pointers, configures git hooks       |
| `uuid5-gen.sh`                  | Generate deterministic UUID5 for note frontmatter                                          |
| `doctor.sh`                     | Runs the full agentBrain health audit (`--fix` auto-repairs the mechanical class first)    |
| `fix.sh`                        | Idempotent auto-repair: clients.md drift, skill symlinks, exec bits, missing local dirs    |
| `render-findings-backlog.sh`    | Renders open findings into `local/backlog/auto-findings-triage.md` (loop-tick ACT step)    |
| `privacy-scan.sh`               | Pre-commit hook: scans for secrets in public files                                         |
| `check-readmes.sh`              | Checks README coverage for public markdown folders                                         |
| `check-frontmatter.sh`          | Checks public markdown frontmatter/schema hygiene                                          |
| `check-session-schema.sh`       | Checks session continuity naming/schema rules                                              |
| `check-pi-lens.sh`              | Checks unresolved local Pi-lens worklog findings                                           |
| `check-pi-extension-types.sh`   | Type-checks Pi extensions using `npm exec --package typescript` when local tsconfig exists |
| `test-pi-extensions.sh`         | Runs lightweight unit tests for pure Pi extension helpers                                  |
| `check-links.sh`                | Checks public wiki-link targets                                                            |
| `check-path-naming.sh`          | Reports path naming drift (lowercase/kebab-case audit)                                     |
| `check-agentbrain-local.sh`     | Validates `local/` structure and content                                                   |
| `check-brain-review.sh`         | Semantic quality checks: stale notes, duplicates, misclassification                        |
| `test-session-continuity.sh`    | Tests session archive naming, collision, chain, and frontmatter                            |
| `sync-agentbrain-local.sh`      | Syncs `local/` changes to its own git repo                                                 |
| `publish-agentbrain-github.sh`  | Publishes public repo to GitHub                                                            |
| `update-daily-note.sh`          | Generates/updates daily notes                                                              |
| `lightpanda-install.sh`         | Installs Lightpanda browser                                                                |
| `lightpanda-install-wrapper.sh` | Wrapper for Lightpanda install with error handling                                         |

## Usage

```bash
# First time setup
bash scripts/setup.sh

# Generate a UUID5 for a new note
bash scripts/uuid5-gen.sh "learnings/My-New-Note"

# Run full health audit
bash scripts/doctor.sh

# Validate local structure only
bash scripts/check-agentbrain-local.sh

# Type-check Pi extensions on machines bootstrapped for Pi
bash scripts/check-pi-extension-types.sh

# Run Pi extension helper tests
bash scripts/test-pi-extensions.sh
```

## Reconfigure reference

What to run when something changes — no need to re-run full setup.

| What changed | Command |
|---|---|
| **Vault location** (moved to a new path) | `bash scripts/move-agentbrain.sh <new-path>` |
| **Locale / UI language** | `/config` (agentBrain skill) or `export AGENTBRAIN_LOCALE=nl` in shell rc |
| **Agent connections** (add/remove Claude, Copilot, Gemini…) | `bash scripts/setup-agent-integrations.sh` |
| **Add-ons** (install, uninstall, enable, disable) | `bash scripts/addons.sh install <id>` / `bash scripts/addons.sh uninstall <id>` |
| **Pi agent** (update symlinks, skills, extensions) | `bash scripts/configure-pi.sh` |
| **Skills** (re-sync brain skills into agent dirs) | `bash scripts/setup-skills.sh` |
| **Preferences** (personal, team, org) | `/onboard` (agentBrain skill) |
| **Hermes SOUL.md pointer** | `bash scripts/setup-hermes.sh` |
| **Health audit + auto-repair** | `bash scripts/doctor.sh --fix` |
| **Full uninstall** | `bash scripts/uninstall.sh` (add `--purge` to also wipe addon configs) |
