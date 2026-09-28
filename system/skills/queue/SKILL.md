---
name: queue
description: Manage the agentBrain work queue + dispatch via scripts/queue.sh. Use when the user says "queue this", "add a task", "start/finish/cancel a task", "dispatch to <agent>", "what's on the board", "show my queue", or wants to track work with status. Markdown-native task notes under vault/queue/.
---

# Queue skill

Agent-agnostic wrapper around `scripts/queue.sh`. Work-items are `type: task`
notes under `vault/queue/<scope>/`; status lives in frontmatter.

## Commands

| Intent | Command |
|---|---|
| add item | `bash scripts/queue.sh add "<title>" --scope <s> --prio P1 [--verify "<cmd>"] [--blocked-by <id>[,<id>]]` |
| list | `bash scripts/queue.sh list [--scope s] [--status st]` |
| start (one in_progress per scope) | `bash scripts/queue.sh start <id>` |
| finish / cancel | `bash scripts/queue.sh done <id>` · `cancel <id>` |
| block on other items | `bash scripts/queue.sh block <id> <blocker-id>[,<id>]` |
| independent re-check | `bash scripts/queue.sh review <id> --watchdog <agent>` |
| dispatch | `bash scripts/queue.sh dispatch <id> --to <agent>` (handoff) or `--event` (event-bus) |
| refresh board | `bash scripts/queue.sh board` → `vault/queue/index.md` |
| pull completions | `bash scripts/queue.sh consume-completions` |

## Notes

- **Verify**: `verify:` is a shell command that proves the task is done, run from the
  caller's cwd. `done` runs it first; a failing proof refuses `done`, with a separate
  message when the proof itself could not run (exit 126/127). `QUEUE_FORCE=1 ... done`
  overrides and records `verify_overridden: <time> exit <code>`, never `verified:`. No `verify:` means `done` works as before. Remote completions
  (`consume-completions`) go through the same check.
- **Blockers**: only the `blocked_by:` field blocks, never a "blocked by X" line in the
  body. The task goes `blocked` → `pending` once every blocker is `done`; a cancelled
  blocker keeps it blocked (a human decides).
- **Watchdog**: `review` parks the task in `in_review` and emits
  `queue.item.verify.requested`. The watchdog re-checks, never fixes, and answers with
  `queue.item.verified {note_id, verdict: pass|fail, reason}`; `consume-completions`
  applies it (pass → `done`, fail → `pending` with the reason appended to the note).

- `<id>` is the note's uuid5 (`id:` field). Find it via `queue.sh list` or the note.
- Views: `vault/queue/index.md` (board) and daily-notes (timeline). For a curated kanban,
  link tasks from a planning note of your own.
