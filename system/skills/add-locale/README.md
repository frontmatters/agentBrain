---
date: 2026-05-31
type: skill
tags: [skill, i18n, agentbrain]
status: active
id: 606da1bc-e57d-54f7-ba55-a60d072e6dfa
---

# add-locale

Add a new UI language to agentBrain's i18n layer (`scripts/lib/_strings.sh`).

Interactive flow: collects the locale code + display name, extracts all string keys from the canonical English source, prompts for translations, inserts a new `_t_xx()` function, and extends the dispatcher.

See `SKILL.md` for the full procedure and examples.
