---
date: 2026-09-27
type: system
tags: [installer, scripts, tooling]
id: 7539145d-fb5f-5813-8b2f-1a2069d457d0
---

# agentBrain installer

`install.sh` — the engaging first-run installer: brain animation → machine scan
(required gate + recommended report) → install confirmation → guided/quick choice
→ clone (or bundle) → full bootstrap.

Env overrides: `AB_REPO` `AB_BRANCH` `AB_CHANNEL` `AB_DEST` `AB_BUNDLE` (install
from a served git bundle instead of cloning) `AB_REMOTE` (origin after a bundle
install). The default online install remains on public stable `main`.

## Public Next (opt in after an RC is published)

The public `next` branch advances **only** to checked and reviewed RC tags; it
never follows a moving branch. To install the latest public RC:

```bash
curl -fsSL https://raw.githubusercontent.com/frontmatters/agentBrain/next/scripts/installer/install.sh -o /tmp/agentbrain-install-next.sh && \
  AB_CHANNEL=next AB_BRANCH=next bash /tmp/agentbrain-install-next.sh
```

The installer checks the remote Next tip against an `-rc.N` tag before modifying
an existing checkout, pins the release version, and configures `brain update` to
follow RC tags. A LAN bundle, missing tag, dirty existing checkout, or moving
untagged branch is refused. To return to stable: `brain channel set stable`,
then `brain update` (use `--switch` when returning to the older stable version
cannot fast-forward). Your vault is not part of the public checkout.

## Development helpers

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
