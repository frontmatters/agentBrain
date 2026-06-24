---
date: 2026-05-21
type: system
tags: [meta, addons]
id: 5a22279d-c4a9-58bb-b19d-b4db4532046f
---

# Add-ons Layer

Opt-in, agent-agnostic tools that enrich agentBrain without becoming core
dependencies. Public registry here; private machine state in `local/addons/`.

## Layout

- `system/addons/<id>/manifest.md` — registry entry (frontmatter = schema).
- `system/addons/<id>/SKILL.md` — optional skill for clients that support skills.
- `local/addons/<id>/enabled` — touch file; present means enabled (created by `addons.sh`).

## Commands

```bash
bash scripts/addons.sh status         # list add-ons + state (+VERSION/SOURCE columns)
bash scripts/addons.sh status --remote # adds an UPDATE column (fetches registry indexes)
bash scripts/addons.sh search [term]  # merged view: bundled + local + all registries
bash scripts/addons.sh install <id>   # privacy prompt -> install -> enable -> check
bash scripts/addons.sh update <id>    # fetch a newer version from the registries (explicit)
bash scripts/addons.sh new <id> [name] # scaffold your own addon into local/addons/<id>/
bash scripts/addons.sh enable <id>    # enable only
bash scripts/addons.sh disable <id>   # disable
bash scripts/addons.sh check [<id>]   # runtime health of enabled add-ons
bash scripts/addons.sh test [<id>]    # validate manifest + health, per add-on or all
```

## Registries (distribution)

addons.sh discovers addons from **two local roots** — `system/addons/` (bundled
with the framework) and `local/addons/` (your own + everything you install) —
and from any number of **registries**: a Docker-style "app store" model.

A registry is just a URL to a static `index.json`. The **default** registry —
the one used when you don't pin, and the tie-winner for same-`id` addons — is
built in (like npm's `registry` or cargo's `registry.default`). Add more with
`addons.sh registry add <name> <url>`.

```bash
bash scripts/addons.sh registry list                  # default + named registries
bash scripts/addons.sh registry add <name> <url>      # add a named registry
bash scripts/addons.sh registry remove <name>         # remove a named one
bash scripts/addons.sh registry default [<url>|reset] # per-machine default (devs: point at Gitea)
```

Named registries live in `local/addons/registries.json`. The **default** is
always resolved dynamically (precedence: `ADDONS_DEFAULT_URL` env >
`local/addons/default-url` > the baked-in public GitHub default), so re-pointing
it always takes effect and is never frozen by adding other registries. Because
`local/` is excluded from releases, your personal default never changes the
shipped default for anyone else. Downloaded addons unpack into
`local/addons/<id>/` — outside git and releases — so an update can't clobber or
leak them.

### index.json contract

```json
{
  "registry": "agentbrain",
  "updated": "2026-06-12T00:00:00Z",
  "addons": [
    {
      "id": "youtube-knowledge",
      "name": "YouTube Knowledge Sync",
      "version": "1.0.0",
      "url": "https://github.com/OWNER/REPO/releases/download/addon-youtube-knowledge-v1.0.0/addon-youtube-knowledge-v1.0.0.zip",
      "sha256": "…",
      "privacy": "sends-docs"
    }
  ]
}
```

Every install verifies the downloaded zip's `sha256` against the index; a
mismatch hard-fails and unpacks nothing.

### Dupe & version rules

1. **Newest wins within one registry** (semver via `sort -V`).
2. **The default registry beats named ones** for the same `id` — a named
   third-party registry can never silently shadow a default addon
   (dependency-confusion guard).
3. **Pin explicitly** to override: `addons.sh install <registry>/<id>`.
4. `search` shows all sources for a dupe, newest first, marked `← nieuwste`.
5. `install` always prints which source it chose.

### Distributing your own addons (three routes)

1. **Local only** — `addons.sh new <id>` scaffolds into `local/addons/<id>/`;
   it shows up in `status` immediately and the full lifecycle works. Nothing
   leaves your machine.
2. **Your own registry** — `bash scripts/package-addon.sh <id>` builds a
   privacy-scanned `addon-<id>-v<ver>.zip` + `.sha256`; `bash
   scripts/registry-index.sh --url-template <tpl> --dir <zips> --out index.json`
   generates the index. Host it anywhere; others add it via `registry add`.
3. **Public store** — open a PR against the `agentbrain-registry` repo; the
   publish pipeline (`scripts/publish-addon.sh`) regenerates the index.

The framework installer ships **only essential addons**
(`scripts/lib/essential-addons.txt`); everything else is distributed through
registries.

## Testing an add-on

```bash
bash scripts/addons.sh test <id>      # manifest validation + runtime health for one add-on
bash scripts/addons.sh test           # same, for every registered add-on
bash scripts/check-addons.sh <id>     # static manifest validation only
```

`test` always runs static validation; it adds a runtime health check when the add-on is
enabled, and is static-only (still PASS) when the tool is not installed — so a manifest
can be validated without installing anything.

When a manifest declares a `test:` field, `addons.sh test` also runs that suite from the
add-on directory — but only if its runtime (the first word of the command, e.g. `bun`) is
on `PATH`; otherwise it falls back to static validation. Example: `test: bun test`,
`test: bash tests/test-install.sh && bash tests/test-build.sh`.

## Manifest schema

| Field | Required | Values |
| --- | --- | --- |
| `id` | yes | must equal the directory name |
| `name` | yes | display name |
| `install` | for `self`/`config-entry` | shell command |
| `command` | for health check | binary checked via `command -v` |
| `privacy` | yes | `local` \| `sends-docs` \| `sends-all` |
| `install_method` | yes | `self` \| `ai-driven` \| `config-entry` |
| `os` | optional | space/comma-separated `macos` \| `linux` \| `windows` \| `any`; **absent = cross-platform (any)** |
| `test` | optional | shell command run from the add-on dir (its own test suite) |
| `support.<client>` | optional | `full` \| `rules` \| `none` \| `unknown` (agent axis; use `os` for the platform axis) |
| `outputs` | optional | list of produced artifacts |

Static validation: `scripts/check-addons.sh` (doctor-wired). Doctor never fails on a
missing add-on; `addons.sh check` fails only when an *enabled* add-on is broken.

## Add-on types and structure contract

Every add-on is one of four types. The type determines what MUST exist in its
directory. When writing or upgrading an add-on, find the row and provide
exactly what it requires — no more, no less.

| Type | Examples | MUST have | MUST NOT |
| --- | --- | --- | --- |
| **registry-pointer** — points at an external tool/skill collection; nothing runs locally from this dir | anthropic-skills, impeccable, trailofbits-skills, understand-anything, routa, agent-browser | `manifest.md` + `README.md` documenting: what it is, upstream URL, license, install per client, **uninstall**, version-pinning advice, supply-chain note | local code, install.sh |
| **tool** — self-contained CLI/runtime in this dir | youtube-knowledge, graphify, agentbrain-mcp, headroom-proxy, event-bus | `manifest.md` (`install:` that works from vault root), `README.md`, `bin/<id>` entrypoint, tests + `test:` field, uninstall path (script or documented inverse) | hardcoded agent paths unless declared in `support:` |
| **behavior** — installs hooks/config into an agent | claude-memory-redirect, extract-learnings, session-journal, git-email-guard | everything from *tool* minus `bin/` , plus `install.sh` **and `uninstall.sh`** (true inverse: removes every hook/config line install added), `support:` declaring exactly which agents it patches | silent skips when the target agent is missing — print what was skipped |
| **scheduled** — any of the above with a `schedule:` block | weekly-review, youtube-knowledge | `bin/<id>` (launchd entrypoint), non-interactive operation (no prompts on the scheduled path), a documented "what happens when a dependency is missing at 03:00" answer | interactive prompts reachable from the scheduled entrypoint |

Universal rules (all types):
- `id` equals the directory name; manifest frontmatter is the schema.
- The `privacy:` value describes what the add-on **itself** causes to leave the
  machine (`local` | `sends-docs` | `sends-all`). When in doubt, pick the more
  conservative value and explain in the README.
- Any file path named in the manifest (`install:`, `test:`, `command:`-script,
  `schedule.entrypoint`) must exist. A manifest that references a missing file
  is a FAIL.
- Errors must be loud: a missing dependency prints the install command and
  exits non-zero (or, for hooks, exits 0 but logs what it skipped). Never
  `|| true` away a failure without writing a line to stderr.

## Maturity rubric (target: every add-on ≥ 8.0)

Score each add-on on 8 criteria. Re-score after every change.

| # | Criterion | Max |
| --- | --- | --- |
| 1 | Manifest complete & honest (`support:` matches reality) | 1.0 |
| 2 | README: frontmatter, install/usage/uninstall/troubleshooting | 1.0 |
| 3 | Install/uninstall robust & idempotent | 1.5 |
| 4 | Tests present, green, wired via `test:` (n/a for registry-pointers → full marks if docs verifiable) | 2.0 |
| 5 | Error handling: no silent failure modes | 1.5 |
| 6 | Agnosticism: no undeclared agent hardcoding | 1.5 |
| 7 | Privacy classification correct; retention where data persists | 1.0 |
| 8 | Docs match actual behaviour | 0.5 |

## Upgrade playbook (for any model executing add-on improvements)

Work on ONE add-on at a time, in this order:

1. Read the add-on's `manifest.md`, `README.md`, and every script it ships.
2. Determine its type from the table above; list what the contract requires
   that is missing or wrong.
3. Fix in this order: (a) manifest fields & referenced-file existence,
   (b) README gaps (uninstall! troubleshooting!), (c) uninstall script if the
   type requires one, (d) loud error handling, (e) tests + `test:` field.
4. Never change the `id:` in any frontmatter. New `.md` files need frontmatter
   with an id from `bash scripts/uuid5-gen.sh "<vault-relative-path-no-ext>"`.
5. Verify after each fix: `bash scripts/check-addons.sh <id>` then
   `bash scripts/addons.sh test <id>`; finish the add-on with
   `bash scripts/doctor.sh --ci` (must stay green) before starting the next.
6. If a fix requires a judgement call the contract doesn't answer (privacy
   reclassification, support-matrix claims you cannot verify locally): stop
   and flag it for the owner instead of guessing.
