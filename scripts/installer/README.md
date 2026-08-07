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
