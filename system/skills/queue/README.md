---
date: 2026-08-02
type: system
tags: [skill, queue, tasks, dispatch]
id: 93bbc92a-3c88-5204-a118-4be858406de6
---

# Queue skill

Agent-agnostic wrapper around `scripts/queue.sh` — the markdown-native work queue
+ dispatch. Items are `type: task` notes under `local/queue/<scope>/`; status lives
in frontmatter. See `SKILL.md` for the command surface (add/start/done/dispatch/board).
