---
date: 2026-05-18
type: system
tags: [skill, doctor, health]
id: 575271b7-91d5-5cbb-bc9e-f67d3bbdb223
---

# doctor

Health audit skill for agentBrain itself.

## Purpose

Checks whether the brain framework is functioning correctly: privacy guardrails, README coverage, frontmatter hygiene, session schema, local secret hygiene, and shell script syntax.

## Usage

```bash
/doctor
```

Equivalent commands:

```bash
brain doctor          # this install (doctor.sh --user)
brain doctor --dev    # the agentBrain source: the full doctor with its tests
```

Use `brain doctor` when agentBrain may be inconsistent on a machine, and
`brain doctor --dev` after framework changes or before publishing.
