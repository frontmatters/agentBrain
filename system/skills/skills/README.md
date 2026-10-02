---
date: 2026-07-04
type: system
tags: [skill, skills]
id: 0c280ab2-4ed9-523c-8cd4-5ff878b85dd6
---

# skills — local skill-lifecycle orchestrator

`/skills` is a **thin router** over agentBrain's existing skill tooling. The
deterministic mechanics live in `bin/skills` (catalogue, sources, a heuristic
audit, sync); scaffolding and moves are delegated to the shipped `addon-create`
and `promote` skills and to `addons.sh`. agentBrain ships no skill-discovery
skill and no deep (forking) audit skill: `skills audit` is the audit that ships.

## Commands

```bash
bash bin/skills list        # the catalogue: every skill with source, state, kind, desc
bash bin/skills list --json # the same records as JSON (schema 1), for tools
bash bin/skills sources     # skill-repo / skill-providing addons + enabled state
bash bin/skills audit <x>   # layered audit: instructions + permissions + code patterns
bash bin/skills sync        # check skills.md parity + re-wire enabled skills/addons
bash bin/skills add-repo <url>  # print the orchestrated "add a skill repository" flow
bash bin/skills promote     # how to promote/demote a skill (delegates to /promote)
bash bin/skills help
```

## The catalogue

`skills list` shows every skill: the framework's (`system/skills`), the vault's own
(`skills/` in the vault) and the skill of every add-on that ships a SKILL.md,
whether that add-on is enabled or only available. Columns: name, source (`system`,
`local`, `addon`), state (`installed` for system and local skills; `enabled` or
`available` for add-ons, from the addons.sh state file), kind (the add-on
manifest's `framework`, `adapter` or `vendored`) and description. Everything is
read from the files on each run, so there is no hand-kept list to drift.
`skills list --json` prints the same records with stable keys (`schema: 1`).

`scripts/checks/check-skills-catalogue.sh` (in the doctor) fails when an add-on
SKILL.md is named other than its add-on id or has no description, and warns when
a registry `index.json` on disk lags the manifests (a missing add-on, or a
different version, kind or license). The registry path comes from
`ADDONS_REGISTRY_INDEX` (a colon list of index files or clone dirs) or from
factory.json `addons.registry` / `addons.registryMirror`; with neither it prints
a skip line. Missing skill links for enabled add-ons are reported by
`check-skill-links.sh`, not repeated here.

## Notes

- **Path anchoring.** `vault/` is a symlink to the vault, so walking up from a skill
  file can't reach the checkout that holds `system/` + `scripts/`. The CLI anchors on
  the stable `~/agentBrain` alias (`AGENTBRAIN_HOME` overrides).
- **`audit` is layered, not a plain grep.** It folds in the skill-auditor methodology:
  it checks `SKILL.md` instructions for prompt-injection and `allowed-tools` for
  permission wildcards, and uses precise code patterns that don't false-positive on
  plain function literals or a regex `.exec` method call. It is still heuristic: read
  what it flags before you trust a skill.
- **Adding a skill repository** is modelled as an addon (registry pointer), like
  `anthropic-skills` / `trailofbits-skills`. `add-repo` prints the flow: discover and
  audit the repository's skills → `/addon-create` (scaffold) → `addons.sh enable` →
  `skills sync`. Its first step names `/skill-finder`, a third-party skill agentBrain
  does not ship; without it, review the repository yourself and run `skills audit` on
  each skill.

## Files

- `SKILL.md` — the agent-facing router (routing table + when-not-to-use).
- `bin/skills` — the CLI (list / sources / audit / sync / add-repo / promote).
- `test.sh`: the catalogue in a throwaway brain and vault (run by `check-skill-tests.sh`).

## Related

`addon-create`, `promote`, `addons`.
