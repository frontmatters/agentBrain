---
date: 2026-05-21
type: system
tags: [architecture, privacy, public-private, agent-agnostic, skills, addons, overview]
id: 755044f8-fb0f-52d1-a964-0b2b418650a1
---

# agentBrain Architecture

> If you are an AI agent reading this: agentBrain is **the brain** — the single source
> of truth for knowledge, rules, skills, and preferences. You do not copy it; you **link
> into it**. This document explains the whole system so you can read and use it correctly.

## 0. Start here (the 1-minute map)

**Two layers:** `system/` = the public framework (ships, versioned). Your **vault**
= your runtime + knowledge, mounted at `vault/` (never ships, gitignored from the
framework). `vault/` is the path; the vault is the thing — by default a directory
inside the checkout, and a symlink to `~/.agentBrain/vault` when one exists, so the
same vault can serve several checkouts and machines.
An optional third knowledge layer, `shared/`, holds knowledge you share with
others via its own scope repo — see [`docs/shared-vault.md`](../docs/shared-vault.md)
for the three-knowledge-layers model.

**Five "things" — which is which:**

| Thing | What it is | Lives in | Add one with |
| --- | --- | --- | --- |
| **skill** | a capability an agent invokes (`SKILL.md`) | `system/skills/` (public) · `vault/skills/` (private) | create the dir + `SKILL.md`; `setup-skills.sh` links it |
| **addon** | opt-in, agent-agnostic tool/behavior (manifest + optional install) | `system/addons/` (bundled) · `vault/addons/` (yours/downloaded) | `addons.sh new <id>` |
| **registry** | a remote catalogue (`index.json`) addons install from | configured in `vault/addons/registries.json` (+ dynamic default) | `addons.sh registry add <name> <url>` |
| **preference** | how you want agents to behave (notes) | `vault/preferences/{personal,team,organization}/` | `/onboard <scope>` |
| **space** | a sealed per-owner compartment of `vault/` (an employer/client) | `vault/spaces/<slug>/` (private; gitignored, off default recall) | `new-space.sh <slug>` (create) · `sync-space.sh` (seal) · see `docs/spaces.md` |

**Task → entrypoint:**

| I want to… | Go to |
| --- | --- |
| install / connect an AI client | `./setup.sh` |
| change config after setup | `/config` (or `addons.sh`, `/onboard <scope>`) |
| add/install/publish an addon | `addons.sh` (§6) + `package-addon.sh`/`publish-addon.sh` |
| check the brain is healthy | `scripts/checks/doctor.sh` (full) · `--fast` (quick pre-push gate) |
| ship dev → live | the dev→live deploy — see *Development and release model* (dev-only tooling, not shipped) |
| cut a release | bump version → curate CHANGELOG [Unreleased] → build + publish; see *Development and release model* |

**Scripts by family** (overview: [`scripts/README.md`](../scripts/README.md); each script self-documents in its header): `setup-*`/`configure-*` (install & connect) ·
`check-*`/`test-*` (validation, run by `doctor.sh`) · `addons.sh` + `*-addon*` +
`registry-*` (addon/registry lifecycle) · `release.sh`/`bump-version.sh`/
`publish-*`/`deploy-*`/`dev-sync-*` (dev/release, never shipped) ·
`brain.sh`/`new-note.sh`/`*-agentbrain-*` (brain ops).

## 1. What agentBrain is

A portable, **agent-agnostic** knowledge system. One repository whose canonical path and
`namespace` UUID are recorded in `brain.json` (it lives under the user's home directory).
Any AI client (Claude Code, Pi, Cursor, Copilot, Gemini, OpenCode, Windsurf, Cline) reads
the same brain. Knowledge lives **once**, in agentBrain; each client connects to it.

Core invariant: **one home, many links.** Skills, rules, and preferences are not
duplicated per client — each client symlinks/points into agentBrain.

**The source of truth must itself be agent-agnostic.** Platform- or vendor-specific
directories — `.github/` (GitHub-specific), `~/.claude/`, `~/.pi/`, `.cursor/`, etc. — are
**never** the canonical home for skills or any brain content. They may only hold *links*
into the agnostic source. If a path is named after a tool, it is a link target, not the
home. Skills therefore live in the agnostic home `system/skills/`; `.github/skills/`
(for GitHub Copilot) holds only symlinks into it, and Pi links the same sources into
`~/.pi/agent/skills/`. Incoming skills should be reviewed — frontmatter, dedup,
agnostic-ability — before landing in `system/skills/`. See §5.

## 2. Layout (the layers)

```text
agentBrain/
  system/            PUBLIC framework — HOW/WHERE (this layer is shareable on GitHub)
    rules.md           canonical public/private + write-location policy (read first)
    architecture.md    this document
    context-tiers.md   hot/warm/cold loading policy
    skills.md          skill index + authoring guidance
    agent-config/      per-client behaviour (shared.md + claude.md/pi.md/cursor.md/…)
    addons/            opt-in, agent-agnostic external tools (registry + clients.md)
    pi-config/         Pi runtime: extensions, skills, setup/bootstrap
    integrations/      first-party integrations (e.g. opensrc)
    lifecycle.md, sessions.md, security-guidance.md
  .github/
    skills/            agentBrain's own skills (brain-review, onboard, save-learning, …)
    copilot-instructions.md, workflows/
  scripts/             setup, validation (check-*.sh), doctor, lifecycle, addons.sh
  templates/           note/project templates with dummy content
  docs/                public documentation (e.g. the shared/ knowledge layer)
    vault/             seeds for the vault (READMEs, registry, preference templates);
                       rendered into vault/ once by setup, mirroring its layout
  vault/ -> ~/.agentBrain/vault    YOUR VAULT — WHAT (symlink; gitignored; real knowledge)
  vault  -> local                  the same directory under its own name (see uuid5-gen.sh)
    spaces/<slug>/     sealed per-owner compartment (gitignored; off default recall)
  shared/ -> ~/.agentBrain/shared  optional SHARED knowledge layer (symlink; gitignored)
  brain.json         manifest: namespace UUID + canonical path
```

## 3. Public / Private rule

**Public = HOW and WHERE. Private = WHAT.**

The public layer (`system/`, `.github/`, `scripts/`, `templates/`) is the framework:
structure, rules, templates, skills, setup helpers, guardrails. Your vault
(`vault/`) holds actual knowledge: discoveries, research, project context, preferences,
infrastructure, troubleshooting history.

Allowed in public: storage locations/conventions, templates with dummy content, agent
instructions and skills, privacy guardrails/scanners, setup scripts without personal
defaults, public-safe docs about the system.

Never in public: real learnings, project/customer/product names, personal tool
evaluations, research notes, private infra (hosts, IPs, paths, repo URLs), security/
credential logs, personal preferences.

Private content lives under:

```text
vault/learnings/  vault/research/  vault/projects/  vault/memories/
vault/preferences/{organization,team,personal}/  vault/integrations/
vault/security/  vault/youtube-digest/  vault/addons/  vault/sessions/
```

`vault/` may be its own private Git repo (self-hosted Gitea or private GitHub), ignored
by the parent public repo. Never store raw credentials/keys/auth files there.

**Promotion:** default = do not promote private knowledge to public. Promote only when
explicitly asked, and only as a sanitized method/example with private context removed.

## 4. How agents connect (the integration model)

Each client reaches agentBrain through its own mechanism. The brain is one; the wiring
differs per client. `scripts/setup/setup-agent-integrations.sh` orchestrates per-client setup.

| Client | Mechanism | Set up by |
| --- | --- | --- |
| Claude Code | appends an `## agentBrain` pointer block to `~/.claude/CLAUDE.md` (idempotent, marker `# agentBrain`). Skill symlinks (`~/.claude/skills/* → system/skills/*`) are wired by `scripts/setup/setup-skills.sh`; `scripts/checks/check-skill-links.sh` guards against drift. | `setup-claude-code.sh` |
| Pi | deep symlinks: `~/.pi/agent/*` → agentBrain (extensions, skills, `AGENTS.md`, `bin/pi`) | `configure-pi.sh` (run via the macOS bootstrap) |
| Cursor/Copilot/Gemini/OpenCode/Windsurf/Cline | per-client rules/config pointing at agentBrain | `setup-{cursor,copilot,gemini-cli,opencode,windsurf,cline}.sh` |

**Reading order for an agent at session start**: the canonical list lives in
`system/rules.md` (Self-Learning Protocol, Step 1) — identical to the pointer block
that `scripts/agentbrain-pointer.sh` installs into every client config. Use
`system/context-tiers.md` to decide what is hot (always) vs warm (on demand) vs cold.

## 5. Skills

Skills follow the same agent-agnostic + public/private rules as all brain content. The
canonical home is the agnostic `system/skills/` — **not** `.github/` (GitHub-specific),
which is only a discovery link.

```text
system/skills/             agnostic home — public framework skills (the source)
.github/skills/<name>      symlink into system/skills/ (GitHub Copilot reads it natively)
~/.pi/agent/skills/<name>  link into system/skills/ (Pi; created by configure-pi.sh)
system/pi-config/skills/   Pi-specific skills only (e.g. pi-postinstall-patch)
```

One source, many links: a skill is authored once under `system/skills/`, and every client
points at it. `.github/skills/` entries are symlinks, never real files — enforced by
`scripts/checks/check-architecture.sh` so the source cannot drift back into a vendor directory.
Skills that only make sense for one agent (e.g. Pi's post-install patch) stay in
`system/pi-config/skills/`. Private or personal skills live under `vault/skills/`;
they are discovered and linked by `scripts/setup/setup-skills.sh` and guarded by
`scripts/checks/check-skill-links.sh`. Incoming skills should be reviewed — frontmatter, dedup,
agnostic-ability — before landing in `system/skills/`.

Skill `SKILL.md` frontmatter: `name`, `description`, optional `argument-hint`,
`user-invocable`, `resources`. Index + authoring guidance: `system/skills.md`.

## 6. Add-ons (`system/addons/`)

Opt-in, agent-agnostic external tools that enrich agentBrain without becoming core
dependencies. Registry: `system/addons/<id>/manifest.md` (frontmatter = schema) + optional
`SKILL.md`. Per-machine state: `vault/addons/<id>/enabled` (touch file). Managed by one
script `scripts/addons.sh` (`status`/`install`/`enable`/`disable`/`check`/`test`).
Static manifest validation (`scripts/checks/check-addons.sh`) is doctor-wired and may fail on a
malformed manifest; runtime health (`addons.sh check`) is separate and never makes core
`doctor` fail on a missing tool. Per-client support in `system/addons/clients.md`.

## 7. Pi runtime (`system/pi-config/`)

Pi-specific layer: `extensions/` (TypeScript Pi extensions sharing `brain-paths.ts` for
vault-relative paths), `skills/`, and `setup/bootstrap-pi-macos.sh`. Pi loads these via
the `~/.pi/agent/*` symlinks. This is the deepest integration — Pi physically runs
agentBrain's extensions and skills.

## 8. Validation & health (`scripts/`)

`scripts/checks/doctor.sh` orchestrates a suite of `check-*.sh` validators and shellcheck:

- `privacy-scan.sh` — blocks personal/private data from the public layer (also a pre-commit hook)
- `check-frontmatter.sh` — note schema (`date/type/tags/UUID id`); SKILL.md + addon manifests are exempt (own schemas)
- `check-readmes.sh` — every public markdown folder has a README (addon subdirs exempt)
- `check-links.sh`, `check-path-naming.sh`, `check-preference-scopes.sh`, `check-session-schema.sh`, `check-addons.sh`, `check-pi-lens.sh`, …

`doctor.sh --ci` is CI-safe; `--summary` compact; `--verbose` shows detail incl. add-on
status. Doctor never fails on a missing add-on. Run doctor green before committing public
changes; `privacy-scan.sh` must pass.

## 9. Lifecycle (`scripts/`)

`setup.sh` orchestrates modular setup: `setup-structure.sh`, `setup-templates.sh`,
`setup-brain-config.sh`, `setup-agent-integrations.sh` (per-client), `setup-git-hooks.sh`,
`setup-validation.sh`. Other lifecycle: `bootstrap-macos.sh`, `offboard.sh` /
`import-offboard.sh` (export/import your vault between machines), `move-agentbrain.sh`,
`uninstall.sh`, `ensure-daily-note.sh`.

## 10. Casing and naming

- Public top-level dirs use canonical names: `system/`, `scripts/`, `templates/`,
  `docs/` (lowercase). The casing was normalized; verify the git-tracked casing,
  not just APFS resolution (case-insensitive locally, case-sensitive on CI/Linux).
- Public learning category files use PascalCase when they are templates/examples.
- Private/`vault/` directories and project folders use lowercase kebab-case.
- Avoid spaces in new directory names; existing historical public dirs may remain for
  compatibility. Root-level project/research files are not allowed; use `vault/research/`.

## Development and release model

`agentBrain-dev` is the **development environment** and the **release source**. The live
checkout is what you install and use; fresh installs come from a release archive built in dev.

### Checkouts, alias, and vault symlinks

The two checkouts (live and dev) differ **only in framework code** (`system/`, `scripts/`);
persistence is shared between them:

- `vault/ -> ~/.agentBrain/vault` — the same vault, symlinked identically into
  both checkouts (same inode), so notes/projects/learnings live exactly once.
- `shared/ -> ~/.agentBrain/shared` — the optional shared layer, likewise symlinked
  identically in both.
- An alias symlink (e.g. `~/agentBrain`) points at the **active** checkout;
  `scripts/brain.sh` (`brain use dev|live`) flips the alias. Because the vault is
  shared, a flip never touches knowledge. `brain status` shows which checkout is active.

Three boundaries — what ships where:

- **Installer** — `release.sh` (a dev-only script) builds `agentBrain-v<VERSION>.zip`: the
  clean, installable public framework. Excludes `.git/`, `vault/`, `brain.json`, generated
  caches, **and** the dev/release tooling listed below.
- **Live sync** — `deploy-dev-to-live.sh` (dev-only) syncs dev's public layer into the live
  checkout, preserving live's `.git/`, `vault/`, and `brain.json`, and excluding the same
  dev/release tooling.
- **Dev-only (never ships)** — release/maintainer tooling only: `VERSION` and
  `scripts/{release,bump-version,publish-gitea-release,dev-sync-status,deploy-dev-to-live,release-check}.sh`.

What DOES ship: the whole framework (`system/` incl. `system/skills/`, `scripts/setup-*`,
`templates/`, `.github/skills/` symlinks) — **including all skills**. Skills are framework, not dev-only:
`capture-tool-info` and `refactor-brain` ship to live and the installer. `vault/` is
private and never ships.

Acceptance for a clean source of truth:
- `deploy-dev-to-live.sh --dry-run` reproduces the current live public layer (no unintended drift).
- `release.sh` produces an archive with no `vault/`, no `brain.json`, and no dev/release tooling.

## 11. Build order (the four layers)

A useful mental model for building up agentBrain is the four-layer progression:

1. **Context** — who you are, your preferences, your knowledge. Seed with `/onboard`
   and `/grill-me`. Lives in `vault/preferences/` and `vault/learnings/`.
2. **Connections** — live data from external tools (calendar, email, project
   management). Pattern: scoped API keys stored in `vault/security/`, documented in
   `vault/integrations/`. See "keys not prompts" in `system/agent-config/shared.md`.
3. **Capabilities** — reusable skills (`system/skills/`) and opt-in add-ons
   (`system/addons/`). Iterate after every use; the brain improves from each run.
4. **Cadence** — automated runs while you are away. launchd loop (`loop-tick.sh`,
   installed via `setup-launchd-loop.sh`). Only automate what is battle-tested first.

The layers are additive: you can have a useful brain with just layer 1. Add 2–4
incrementally as the value of each becomes clear.

## Related

- `system/rules.md` (policy) · `system/skills.md` · `system/context-tiers.md`
- `system/addons/README.md` · `system/agent-config/shared.md`
