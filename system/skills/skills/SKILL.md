---
name: skills
description: >-
  Single entry point for managing agentBrain's OWN skill inventory and lifecycle.
  Use when the user wants the skills catalogue (every system, local and add-on
  skill with its state and kind, also as JSON), check or
  repair the skills.md index and agent wiring, statically pre-scan a skill for
  risky patterns, add a new skill repository, or promote/demote a skill.
  Triggers: "which skills do I have", "list my skills", "manage skills",
  "add a skill repo", "sync the skill index", "is this skill safe",
  "promote this skill". Thin router — it delegates external discovery to
  skill-finder, deep security audit to skill-auditor, repo scaffolding to
  addon-create, and local↔system moves to promote. NOT for searching the
  internet for new skills — use skill-finder directly for that. skill-finder
  and skill-auditor are third-party skills that agentBrain does not ship;
  install them separately to use those steps.
related: [import-external-skill]
---

# skills — local skill lifecycle orchestrator

One entry point for the skills you already have. This is a **thin router**: the
deterministic mechanics live in `bin/skills`; anything that needs judgement is
delegated to a skill that already exists. It adds no new logic of its own — that
is the whole point (no duplication of `addons.sh`, `skill-finder`, `promote`).

## The CLI (deterministic mechanics)

```bash
bash bin/skills list        # the catalogue: every skill with source, state, kind, desc
bash bin/skills list --json # the same records as JSON (schema 1), for tools
bash bin/skills sources     # skill-providing / skill-repo addons + enabled state
bash bin/skills audit <x>   # layered audit: instructions + permissions + code (skill-auditor method)
bash bin/skills sync        # check skills.md parity + re-wire enabled skills/addons
bash bin/skills help
```

`list` / `sources` / `audit` / `sync` are fully scriptable, so the CLI does them
directly. Everything below needs an agent skill, so the CLI only prints the exact
next command — the agent invokes it.

## The catalogue (`list`)

`list` is the one place that shows every skill agentBrain has. It is derived from
the files each time; there is no second list to keep in sync.

| Column | Values | Read from |
|---|---|---|
| name | the skill's directory (an add-on skill is named by its add-on id) | the tree |
| source | `system`, `local` (the vault's `skills/`), `addon` | where the SKILL.md lives |
| state | `installed` (system, local); `enabled` or `available` (add-on) | `<vault>/addons/<id>/enabled`, the addons.sh state (`ADDONS_STATE` overrides) |
| kind | `framework`, `adapter`, `vendored` (add-ons only) | the add-on `manifest.md` |
| description | SKILL.md `description:` (folded text joined) | the SKILL.md |

Every add-on that ships a SKILL.md is listed, enabled or not; an add-on installed
into the vault wins over the bundled copy of the same id, as in `addons.sh`. An
`available` add-on is one `bash scripts/addons.sh enable <id>` away from being
linked. `--json` prints `{"schema": 1, "skills": [...]}` with the keys `name`,
`source`, `state`, `kind` (null outside add-ons), `description`, `deprecated`
(boolean) and `replaced_by` (null or a skill name).

The doctor keeps it honest: `scripts/checks/check-skills-catalogue.sh` fails when
an add-on SKILL.md `name:` is not the add-on id or its description is missing,
and warns when a registry `index.json` on disk lags the manifests (missing
add-on, version, kind or license; path from `ADDONS_REGISTRY_INDEX` or
factory.json, skipped when absent). An enabled add-on without a skill link is
`check-skill-links.sh`'s finding.

## Routing table (what to delegate to)

| User intent | Route to |
|---|---|
| "list / which skills do I have" | `bash bin/skills list` |
| "the skill list for a tool / script" | `bash bin/skills list --json` |
| "what skill sources / repos are active" | `bash bin/skills sources` |
| "is this skill safe" (quick) | `bash bin/skills audit <path>` |
| "is this skill safe" (deep, multi-iteration) | **/skill-auditor** |
| "find / discover / install a skill from the internet" | **/skill-finder** |
| "the index/wiring drifted / new skill not showing up" | `bash bin/skills sync` |
| "promote / demote / make canonical" | **/promote** |
| "add a whole skill repository" | see the flow below |

## Adding a skill repository (the orchestrated flow)

A skill repo is included as an **addon** (like `anthropic-skills`,
`trailofbits-skills`). `bash bin/skills add-repo <url>` prints this checklist;
the agent then runs each agent-skill step:

1. **/skill-finder `<url>`** — discover + security-audit the repo's skills
   (rates SAFE / REVIEW_NEEDED / DANGEROUS). Do not skip on a repo you don't own.
2. **/addon-create** — scaffold the registry-pointer addon (manifest + README with
   upstream, license, install path, supply-chain notes). Vendor into `vault/skills/`
   only if you want the skills versioned with your vault.
3. **`bash scripts/addons.sh enable <id>`** — turn the addon on.
4. **`bash bin/skills sync`** — re-wire it into the agent skill dirs + verify the index.

## When NOT to use

- Discovering/searching the internet for new skills → **/skill-finder** directly.
- A deep, forking security audit of one skill → **/skill-auditor** directly.
- Enabling/disabling arbitrary (non-skill) addons → **`scripts/addons.sh`** directly.

## Status

Framework skill in `system/skills/skills/`; `test.sh` next to this file covers the
catalogue and runs in `check-skill-tests.sh`. Related: `skill-finder`,
`skill-auditor`, and the `addons` / `addon-create` / `promote` skills.
