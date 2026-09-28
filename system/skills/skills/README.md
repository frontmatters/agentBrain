---
date: 2026-07-04
type: system
tags: [skill, skills]
id: 0c280ab2-4ed9-523c-8cd4-5ff878b85dd6
---

# skills — local skill-lifecycle orchestrator

`/skills` is a **thin router** over agentBrain's existing skill tooling. It adds no
logic of its own: the deterministic mechanics live in `bin/skills`, and anything
that needs judgement is delegated to a skill that already exists
(`skill-finder`, `skill-auditor`, `addon-create`, `promote`, `addons.sh`).

## Commands

```bash
bash bin/skills list        # every skill: scope (system/local/addon) + one-line desc
bash bin/skills sources     # skill-repo / skill-providing addons + enabled state
bash bin/skills audit <x>   # layered audit: instructions + permissions + code patterns
bash bin/skills sync        # check skills.md parity + re-wire enabled skills/addons
bash bin/skills add-repo <url>  # print the orchestrated "add a skill repository" flow
bash bin/skills promote     # how to promote/demote a skill (delegates to /promote)
bash bin/skills help
```

## Notes

- **Path anchoring.** `local/` is a symlink to the vault, so walking up from a skill
  file can't reach the checkout that holds `system/` + `scripts/`. The CLI anchors on
  the stable `~/agentBrain` alias (`AGENTBRAIN_HOME` overrides).
- **`audit` is layered, not a plain grep.** It folds in the skill-auditor methodology:
  it checks `SKILL.md` instructions for prompt-injection and `allowed-tools` for
  permission wildcards, and uses precise code patterns that don't false-positive on
  plain function literals or a regex `.exec` method call. It is still heuristic — for a
  forking deep audit use `/skill-auditor`.
- **Adding a skill repository** is modelled as an addon (registry pointer), like
  `anthropic-skills` / `trailofbits-skills`. `add-repo` prints the flow: `/skill-finder`
  (discover + audit) → `/addon-create` (scaffold) → `addons.sh enable` → `skills sync`.

## Files

- `SKILL.md` — the agent-facing router (routing table + when-not-to-use).
- `bin/skills` — the CLI (list / sources / audit / sync / add-repo / promote).

## Related

`skill-finder`, `skill-auditor`, `addon-create`, `promote`, `addons`.
