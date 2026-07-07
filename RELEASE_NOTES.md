---
date: 2026-06-13
type: system
tags: [release-notes, meta]
id: 44adbede-4034-5198-84db-15d34b296cea
---

# Release Notes

## v1.6.2 — Context-aware writes, Hermes on any host

**The headline:** notes now route themselves to the right space per-write —
inferred from where you work (code-root, env, git remote), never from a leaky
vault-global marker — and the note-id integrity gate became agent- and
tool-agnostic. Plus: the Hermes integration now completes on hosts without bun
(e.g. a Raspberry Pi with only system node).

### Highlights

- **Per-write space context inference**: `new-note.sh` decides the target space
  from path signals per write; the `local/.active-space` marker is fully
  decommissioned (writes and recall both resolve from the per-session env). An
  "ask" policy covers the uncertain case instead of silently defaulting
  owner-work into the personal vault.
- **Agent-agnostic note-id commit gate**: a vault pre-commit hook validates
  every staged note id against `uuid5-gen.sh` — no agent or tool can commit a
  fabricated id, and Pi now blocks bad ids pre-write like Claude Code does.
- **Hermes on any host**: the `agentbrain-mcp` server runs identically under
  bun and node/tsx (its only Bun API was dropped), and `setup-hermes.sh` prints
  a runtime-detected wiring hint until the MCP entry actually exists.
- **`/namecheck`**: sweep a product name across registries, marketplaces,
  domains and social — reporting what's behind each taken resource so you can
  judge conflict risk before claiming a brand.
- **`/skills` orchestrator**, nvm-aware agent-CLI installs on Linux/rpi, and
  preferences surfaced in the agent consult instruction.

**Compatibility:** no action required. `active-space.sh use/show/clear` still
round-trip (with a deprecation warning); set `AGENTBRAIN_CONTEXT=<slug>` per
session instead. Existing vaults are untouched.

## v1.6.1 — Spaces, plus an audit-hardened framework

**The headline:** sealed per-owner compartments ("spaces") for client and employer
knowledge, on top of a framework that went through a full audit sweep — ~90
findings across setup/install, uninstall, onboarding, docs, add-ons and the Pi
extensions, all fixed and verified end-to-end.

### Highlights

- **Spaces**: `local/spaces/<slug>/` keeps confidential knowledge out of the
  personal sync and default recall; deliver a whole space as a stamped package
  and restore it elsewhere. A doctor boundary guard fails the build on seal
  breaches or leaks — also in non-git checkouts.
- **A doctor that guards its own docs** (52 checks): skills-index parity, YAML
  frontmatter validation, reverse inventory, pointer sync. The canonical docs
  describe reality again, and drift now fails the build instead of accumulating.
- **Data-safe uninstall**, correct OpenCode/Cline/Windsurf connectors, pinned
  installers, and an update flow that resolves the repo via the `~/agentBrain`
  alias.
- **Strict TypeScript** for the Pi extensions, compatible with pi-ai 0.80, with
  tests for the security-critical ones (164 addon tests, 26 extension tests).

**Compatibility:** no action required. The youtube-digest rename auto-migrates,
old CLI/skill names keep working, and existing vaults are untouched.

## v1.6.1-prerelease-04 — Audit-fix sweep

**The headline:** a full audit of setup/install, uninstall, onboarding, the
canonical docs, addons, and the Pi extensions — ~90 findings, all fixed and
verified end-to-end (fresh install, idempotent re-run, uninstall, update flow).

### Highlights

- **Data safety:** uninstall now removes only the agentBrain pointer block
  (user content survives, backups kept), honors `AGENTBRAIN_HOME`, and never
  breaks a second checkout's alias.
- **Truthful docs:** `architecture.md` documents the dual-checkout/alias/vault
  symlink model; the skills index is complete (39 skills) and guarded by a new
  doctor parity check (52 checks total).
- **Fail-open closed:** the space-boundary leak scan now works in non-git
  checkouts; the pi-lens check no longer reports long-resolved issues.
- **Correct connectors:** OpenCode writes the `instructions` array; Cline gets
  its own rules file; strict TypeScript for the Pi extensions plus tests for
  the security-critical ones (164 addon tests, 26 extension tests).

See `CHANGELOG.md` for the complete list.

## v1.6.0 — Addon registry

**The headline:** agentBrain add-ons now work like a package registry. Instead of
everything shipping in one big install, the framework ships a slim core and
distributes add-ons through registries — a Docker/npm-style "app store" model.
A fresh install can search, install, update, and remove add-ons out of the box.

### What's new

**A registry model for add-ons**
- A registry is just a static `index.json` listing add-ons with a download URL
  and a `sha256`. The public **default** registry is built in; you can add your
  own with `addons.sh registry add <name> <url>`.
- Every install verifies the downloaded zip against the `sha256` in the index —
  a mismatch hard-fails and unpacks nothing.

**New `addons.sh` commands**
```bash
addons.sh search [term]              # browse bundled + local + registries
addons.sh install <id>               # download, verify, install from the default registry
addons.sh install <registry>/<id>    # pin a specific registry
addons.sh update <id>                # pull a newer version (explicit, never automatic)
addons.sh new <id> [name]            # scaffold your own addon into local/addons/
addons.sh registry list|add|remove|default   # manage registries
addons.sh status [--remote]          # VERSION/SOURCE columns; --remote adds UPDATE
```

**Dual-root discovery** — `addons.sh` now sees both bundled add-ons
(`system/addons/`) and your own/downloaded ones (`local/addons/`). For the same
id the local copy wins, so a framework update can never clobber what you
installed.

**Slim-core installer** — the release ships only essential add-ons
(`agentbrain-mcp`, `event-bus`, `session-journal`, `extract-learnings`);
everything else installs on demand from a registry.

**Distribution tooling** — `package-addon.sh` (privacy-scanned zip + sha256),
`registry-index.sh` (generate a validated index), `publish-addon.sh` (publish to
your Gitea registry), and `mirror-registry-github.sh` (mirror to a public GitHub
registry behind privacy + commit-identity gates).

**Config & transfer** — `addons.sh registry default` sets a per-machine default
registry (devs point it at their own Gitea while the shipped default stays
public). The `offboard`/`import-offboard` export now includes a `config/`
section (registries, default registry, enabled add-ons, locale).

### Resolution & dedupe rules

1. Newest version wins within one registry.
2. The **default** registry beats named registries for the same id — a named
   third-party registry can never silently shadow a default add-on
   (dependency-confusion guard).
3. Pin explicitly with `install <registry>/<id>` to override.

### Upgrade notes

- **Terminology change:** the primary-registry concept is now called **default**
  (npm/cargo convention), not "official". The `registry official` command is now
  `registry default`; the index self-name `agentbrain-official` is now
  `agentbrain`. No action needed for normal use.
- The **default registry is always resolved dynamically** (env >
  `local/addons/default-url` > baked-in public default), so re-pointing it always
  takes effect and is never frozen by adding other registries.
- Existing installs keep working; non-essential add-ons that were bundled before
  are now installed from the registry instead.

### Verified

Fresh-install end-to-end against the public registry: search → download →
sha256 verify → unpack → the add-on's own `install.sh` runs → enable →
uninstall. Both an `install.sh` add-on and an ai-driven add-on were exercised.
