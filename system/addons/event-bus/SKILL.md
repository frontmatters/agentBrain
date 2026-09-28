---
name: event-bus
description: Filesystem-based pub/sub for cross-agent communication via JSON events. Use when the user wants to send an event to another agent ("send event to Pi", "emit a review-request"), poll for incoming events ("wait for Pi's reply", "check inbox"), check if an agent is alive ("ping Pi", "is Pi reachable"), or set up async multi-agent workflows. Wraps brain-emit, brain-poll, brain-ping and brain-name CLIs. No daemon, no broker — just JSON files + atomic rename + cursor.
---

# event-bus skill

Filesystem-based pub/sub for agent collaboration. Four CLIs:

| Binary | Purpose |
|---|---|
| `brain-emit` | Place an event in the inbox (returns `event_id`). |
| `brain-poll` | Read events since cursor (filtered by topic/to/from). |
| `brain-ping` | Round-trip latency check against a specific agent. |
| `brain-name` | This session's bus name (`adjective-animal`, djb2-based generator). |

## Location

```
~/agentBrain/system/addons/event-bus/bin/
```

CLIs are directly invokable via shebang — no `bash` prefix needed:

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-emit ...
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-poll ...
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-ping ...
```

## Intent → command mapping

| User intent | Command |
|---|---|
| "send event to Pi" / "emit X" | `brain-emit --type=<topic> --to=pi --from=claude --payload='...'` |
| "check replies" / "poll inbox" | `brain-poll --to=claude --since=<cursor>` |
| "is Pi reachable" / "ping agent" | `brain-ping --to=pi` |
| "listen on the bus" / "what is my name" | `NAME=$(brain-name)`, then `brain-poll --agent=$NAME --commit` in a loop |
| "request review from Pi" | emit `peer-review.review.requested` → wait for `peer-review.review.completed` (see `peer-review` skill — already wired) |

## Naming a listener

Every listener needs its own agent name. Two listeners with one name share one
cursor (`cursors/<host>/<agent>/`), so whichever polls first marks an event seen
and the other never gets it. Do not listen as plain `claude`.

`brain-name` derives the name from the Claude Code session id
(`$CLAUDE_CODE_SESSION_ID`), or from a key you pass: `brain-name <key>`. It uses
a djb2-based generator (64 adjectives x 64 animals), so a key always yields the same
name, such as `calm-robin`. Announce it with a `system.listener.started` broadcast.

## Topic convention

`<addon-or-skill>.<noun>.<verb-past>`:
- `peer-review.review.requested` / `peer-review.review.completed`
- `addon.install.requested` / `addon.install.completed`
- `agent.handoff.requested`

## Event format

JSON with fields: `event_id`, `type`, `from`, `to` (or `any`), `payload` (object), `timestamp`, `correlation_id` (optional for request-reply).

Files land in `vault/events/inbox/<ts>-<topic>-<id8>.json`. Atomic rename guarantees readers never see half-written events.

## When to use vs. when not

**Use it for**:
- Async cross-agent workflows (peer-review, multi-step orchestration)
- Cross-machine sync via the vault's git remote (events sync along)
- Audit trail of what agents say to each other

**Don't use it for**:
- Real-time low-latency comms (poll-based, no push)
- High-volume telemetry (1 event = 1 file, file-system overhead)
- Direct in-process calls (just call the function)

## For agents

When the user wants an agent-to-agent flow: use this instead of inventing a file handoff. Follow the topic-naming convention. When unsure whether a topic already exists: `brain-poll --type-prefix=<prefix> --since=0` to see history.

## References

- README: `system/addons/event-bus/README.md`
- Spec: `system/addons/event-bus/SPEC.md` (if present)
- Related skill: `system/skills/peer-review/SKILL.md` (a consumer of this bus)
