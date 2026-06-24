---
date: 2026-06-13
type: system
tags: [release-notes, meta]
id: 44adbede-4034-5198-84db-15d34b296cea
---

# Release Notes

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
