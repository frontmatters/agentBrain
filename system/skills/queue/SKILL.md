---
name: queue
description: Manage the agentBrain work queue + dispatch via scripts/queue.sh. Use when the user says "queue this", "add a task", "start/finish/cancel a task", "dispatch to <agent>", "what's on the board", "show my queue", or wants to track work with status. Markdown-native task notes under local/queue/.
---

# Queue skill

Agent-agnostic wrapper around `scripts/queue.sh`. Work-items are `type: task`
notes under `local/queue/<scope>/`; status lives in frontmatter.

## Commands

| Intent | Command |
|---|---|
| add item | `bash scripts/queue.sh add "<title>" --scope <s> --prio P1` |
| list | `bash scripts/queue.sh list [--scope s] [--status st]` |
| start (one in_progress per scope) | `bash scripts/queue.sh start <id>` |
| finish / cancel | `bash scripts/queue.sh done <id>` · `cancel <id>` |
| dispatch | `bash scripts/queue.sh dispatch <id> --to <agent>` (handoff) or `--event` (event-bus) |
| refresh board | `bash scripts/queue.sh board` → `local/queue/index.md` |
| pull completions | `bash scripts/queue.sh consume-completions` |

## Notes

- `<id>` is the note's uuid5 (`id:` field). Find it via `queue.sh list` or the note.
- Views: `local/queue/index.md` (board), `[[planning]]` (curated kanban), daily-notes (timeline).
- Design: `[[2026-08-02-queue-dispatch-design]]`.
