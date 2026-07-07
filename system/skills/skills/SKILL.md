---
name: skills
description: >-
  Single entry point for managing agentBrain's OWN skill inventory and lifecycle.
  Use when the user wants to list installed skills (system + local), check or
  repair the skills.md index and agent wiring, statically pre-scan a skill for
  risky patterns, add a new skill repository, or promote/demote a skill.
  Triggers: "which skills do I have", "list my skills", "manage skills",
  "add a skill repo", "sync the skill index", "is this skill safe",
  "promote this skill". Thin router — it delegates external discovery to
  skill-finder, deep security audit to skill-auditor, repo scaffolding to
  addon-create, and local↔system moves to promote. NOT for searching the
  internet for new skills — use skill-finder directly for that.
---

# skills — local skill lifecycle orchestrator

One entry point for the skills you already have. This is a **thin router**: the
deterministic mechanics live in `bin/skills`; anything that needs judgement is
delegated to a skill that already exists. It adds no new logic of its own — that
is the whole point (no duplication of `addons.sh`, `skill-finder`, `promote`).

## The CLI (deterministic mechanics)

```bash
bash bin/skills list        # every skill: scope (system/local/addon) + one-line desc
bash bin/skills sources     # skill-providing / skill-repo addons + enabled state
bash bin/skills audit <x>   # layered audit: instructions + permissions + code (skill-auditor method)
bash bin/skills sync        # check skills.md parity + re-wire enabled skills/addons
bash bin/skills help
```

`list` / `sources` / `audit` / `sync` are fully scriptable, so the CLI does them
directly. Everything below needs an agent skill, so the CLI only prints the exact
next command — the agent invokes it.

## Routing table (what to delegate to)

| User intent | Route to |
|---|---|
| "list / which skills do I have" | `bash bin/skills list` |
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
   upstream, license, install path, supply-chain notes). Vendor into `local/skills/`
   only if you want the skills versioned with your vault.
3. **`bash scripts/addons.sh enable <id>`** — turn the addon on.
4. **`bash bin/skills sync`** — re-wire it into the agent skill dirs + verify the index.

## When NOT to use

- Discovering/searching the internet for new skills → **/skill-finder** directly.
- A deep, forking security audit of one skill → **/skill-auditor** directly.
- Enabling/disabling arbitrary (non-skill) addons → **`scripts/addons.sh`** directly.

## Status

Experimental, lives in `local/skills/`. Promote to `system/skills/` (via **/promote**)
once it has earned it (the 2×-proven rule). Related: `skill-finder`,
`skill-auditor`, and the `addons` / `addon-create` / `promote` skills.
