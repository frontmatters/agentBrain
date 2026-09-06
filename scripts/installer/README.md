---
date: 2026-08-07
type: system
tags: [installer, scripts, tooling]
id: 7539145d-fb5f-5813-8b2f-1a2069d457d0
---

# agentBrain installer

`install.sh` — the engaging first-run installer: brain animation → machine scan
(required gate + recommended report) → install confirmation → guided/quick choice
→ clone (or bundle) → full bootstrap.

Env overrides: `AB_REPO` `AB_BRANCH` `AB_DEST` `AB_BUNDLE` (install from a served
git bundle instead of cloning) `AB_REMOTE` (origin to set after a bundle install).

`serve-lan.sh` — dev helper: rebuilds the bundle from current `main`, injects LAN
defaults into a served copy under /tmp, and starts the HTTP server. One command to
refresh what a second machine installs.

`sandbox.sh` — dev helper: a disposable install-testbed in the browser. Serves a
real terminal (ttyd) where every connection spawns a fresh non-root Debian
container; paste the install curl and walk the real installer + wizard as a human
on a brand-new machine. `start | stop | status`; a wrapper page adds a reset
button. Composes with serve-lan.sh (run that first). Needs docker + ttyd.

## The installer is one versioned unit

The unit = this orchestrator (`install.sh`) + the sub-installers it calls
(`bootstrap/macos.sh`, `setup.sh`, `setup-devtools.sh`, `install-*.sh`) + the
shared libs they source (`platform.sh`, `lib/capability-install.sh`,
`prompt-helper.sh`, `lib/_toolpaths.sh`) + their wiring (the steps and offers
in install.sh).

**Versioning:** `VERSION` in this directory is the unit version
(`INSTALLER_VERSION`; env `AB_INSTALLER_VERSION` overrides). Bump it whenever
installer behavior changes — a new step, a new offer, a changed default. It is
independent from the repo `VERSION` (the agentBrain release the installer
targets) and from addon versions (each addon's own manifest/CHANGELOG).

**Packaging question (open, deferred 2026-08-31):** whether this unit should
stay inside the agentBrain repo (self-hosted curl|bash, current) or move to its
own repo — see the installer-rollout loop record, open points.
