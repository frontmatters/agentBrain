---
date: 2026-08-02
type: system
tags: [skill, queue, tasks, dispatch]
id: 93bbc92a-3c88-5204-a118-4be858406de6
---

# Queue skill

Agent-agnostic wrapper around `scripts/queue.sh` — the markdown-native work queue
+ dispatch. Items are `type: task` notes under `vault/queue/<scope>/`; status lives
in frontmatter. See `SKILL.md` for the command surface (add/start/done/dispatch/board).

`brain remind "text" --on YYYY-MM-DD [--scope S]` creates a queue task with a
`due:` field; `brain remind list` orders open dated tasks by due date (overdue
first), and `brain remind done <id>` uses queue's `done`. Past dates require
`--force`; invalid dates are refused. Due tasks surface at session start in
`vault/sessions/startup-context.md`, not through an external scheduler.
