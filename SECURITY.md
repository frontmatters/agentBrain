# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Preferred: GitHub's private vulnerability reporting — the **"Report a vulnerability"**
  button on this repository's **Security** tab. It opens a private advisory only the
  maintainers can see.
- We aim to acknowledge a report within a few days and to coordinate a fix and
  disclosure timeline with you.

## Supported versions

agentBrain ships from `main` with tagged releases. Security fixes land on the
latest release line; please reproduce against the latest tag before reporting.

## What agentBrain touches on your machine

Transparency matters more than the feature itself, so the short version:

- **Core is local-first.** Day-to-day, agentBrain's framework stores knowledge as plain
  Markdown in your private vault (`local/`, by default under `~/.agentBrain/`) and makes
  **no network calls of its own** (setup and bootstrap do fetch dependencies — the `git clone`,
  and on macOS Node/bun — which is visible in the scripts). It writes to: the vault, per-agent
  skills directories (symlinks into the brain, e.g. `~/.claude/skills/`), and — only if you opt
  in during onboarding — a single `export AGENTBRAIN_LOCALE=…` line in your shell rc.
- **Add-ons are opt-in and privacy-gated.** Each add-on declares a `privacy:` level
  (`local`, `local-only`, `sends-docs`, `sends-all`) shown and confirmed before it is
  enabled. Nothing leaves your machine unless you enable an add-on that says so.
- **Credentials are explicit and opt-in.** The core does not read, store, or transmit
  secrets. Credential handling lives in dedicated, opt-in add-ons (e.g. `secrets-helper`)
  whose behavior is documented in their own manifest/README. agentBrain never reads your
  `.env` files or prints token values.
- **Reversible.** `scripts/uninstall.sh` removes what setup added (symlinks, env entries)
  and leaves your vault/data intact.

## Out of scope

- Vulnerabilities in third-party add-ons hosted outside this repository (report those
  to their maintainers), and issues that require an attacker to already have local
  access to your account.
