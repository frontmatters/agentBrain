---
date: 2026-09-26
type: system
tags: [skill, factory, templates]
id: aa739958-df77-58cc-ae28-7c69b3bc98b3
---

# factory-builder templates

Files the factory tools create in a factory. `{project}` and the section
placeholders are filled from `factory.json` and `obeya.defaults.json`.

- `andon.md`: the andon that `factory-obeya.sh --init` writes to the path in
  `obeya.andon`. Its two section headings come from `obeya.sections`.
