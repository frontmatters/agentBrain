---
id: hallmark
name: Hallmark (anti-AI-slop design skill)
version: 0.1.0
author: nutlope
upstream: https://github.com/nutlope/hallmark
license: MIT
install: echo 'hallmark is vendored at vault/skills/hallmark/ - see README.md for the upstream refresh command'
# On by default in a fresh install; the user can untick it.
default_enabled: true
privacy: local
install_method: self
support:
  pi: full
  claude: full
  copilot: unknown
  abh: unknown
outputs:
  - vault/skills/hallmark/**
---

# Hallmark

A design skill for AI coding assistants (Claude Code, Cursor, Codex, and Pi via
this vendored copy). Encodes an anti-AI-slop ruleset — macrostructure choice,
typography, OKLCH color, layout, motion, a 57-gate slop test — across four
verbs: default build, `audit`, `redesign`, `study`. Pure markdown (SKILL.md +
`references/`), no executable code, MIT licensed. Upstream:
<https://github.com/nutlope/hallmark>, made by Together AI.

Vendored (not just referenced) into `vault/skills/hallmark/` so the whole
`references/` tree ships with the skill and every agent (pi/Claude/Copilot)
gets it wired via `scripts/setup/setup-skills.sh`.
