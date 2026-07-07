---
name: event-bus
description: Filesystem-based pub/sub for cross-agent communication via JSON events. Use when the user wants to send an event to another agent ("send event to Pi", "emit a review-request"), poll for incoming events ("wait for Pi's reply", "check inbox"), check if an agent is alive ("ping Pi", "is Pi reachable"), or set up async multi-agent workflows. Wraps brain-emit, brain-poll, brain-ping CLIs. No daemon, no broker — just JSON files + atomic rename + cursor.
---

# event-bus skill

Filesystem-based pub/sub for agent collaboration. Three CLIs:

| Binary | Purpose |
|---|---|
| `brain-emit` | Place an event in the inbox (returns `event_id`). |
| `brain-poll` | Read events since cursor (filtered by topic/to/from). |
| `brain-ping` | Round-trip latency check against a specific agent. |

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
| "request review from Pi" | emit `peer-review.review.requested` → wait for `peer-review.review.completed` (see `peer-review` skill — already wired) |

## Topic convention

`<addon-or-skill>.<noun>.<verb-past>`:
- `peer-review.review.requested` / `peer-review.review.completed`
- `addon.install.requested` / `addon.install.completed`
- `agent.handoff.requested`

## Event format

JSON with fields: `event_id`, `type`, `from`, `to` (or `any`), `payload` (object), `timestamp`, `correlation_id` (optional for request-reply).

Files land in `local/events/inbox/<ts>-<topic>-<id8>.json`. Atomic rename guarantees readers never see half-written events.

## When to use vs. when not

**Use it for**:
- Async cross-agent workflows (peer-review, multi-step orchestration)
- Cross-machine sync via Gitea (events sync along)
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
