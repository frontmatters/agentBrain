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

Equivalent command:

```bash
bash scripts/doctor.sh
```

Use after framework changes, before publishing, or when agentBrain may be inconsistent.
