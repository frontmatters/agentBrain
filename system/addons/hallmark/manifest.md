---
id: hallmark
name: Hallmark (anti-AI-slop design skill)
version: 0.1.0
author: nutlope
kind: vendored
upstream_version: v1.1.0
upstream: https://github.com/nutlope/hallmark
license: MIT
install: echo 'hallmark is not bundled - vendor it into vault/skills/hallmark/ with the command in README.md (Update)'
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
a vendored copy). Encodes an anti-AI-slop ruleset — macrostructure choice,
typography, OKLCH color, layout, motion, a 57-gate slop test — across four
verbs: default build, `audit`, `redesign`, `study`. Pure markdown (SKILL.md +
`references/`), no executable code, MIT licensed. Upstream:
<https://github.com/nutlope/hallmark>, made by Together AI.

Once vendored into `vault/skills/hallmark/` (see README.md, Update), the whole
`references/` tree sits with the skill and every agent (pi/Claude/Copilot)
gets it wired via `scripts/setup/setup-skills.sh`.
