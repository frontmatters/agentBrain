---
date: 2026-09-23
type: spec
tags: [spec]
source: session
version: 0.1.0
id: ea6cf524-be32-5010-8838-4391d74ffd2d
---

# event-bus SPEC-chat. one readable stream across every session

`brain-chat` merges what every agent already writes to the audit log into one
chronological view, with the claims from [[SPEC-claims]] as context. It answers the
question that costs the most when nobody can answer it: *what are the other sessions
doing right now.*

For envelope/routing see [[SPEC]]. For filesystem/cursor see [[SPEC-storage]].

**Status**: reading is `IMPL` (`bin/brain-chat`). Writing is `DESIGN`: the message
format below is fixed so writing can be added later without a migration.

## Why

Two sessions working in one repository can collide without either noticing: one commits
onto the other's branch or switches the shared working tree out from under it. A
messaging tool does not help when neither session knows the other is there.

That is a reading problem, not a writing problem. Colliding sessions already write:
events to the bus, claims to `vault/claims/`, commits to git. Nothing collected it into
something a person or an agent could look at.

### Why not a message board

A chat does not prevent such a collision, because nobody sends a message. Claims
cover that case. What remains is seeing, and a channel nobody looks into is worse than no
channel: it reads as coverage and delivers none.

## Shape

```bash
brain-chat                      # merged, chronological, newest last
brain-chat --follow             # keep watching
brain-chat --since 2h           # a window
brain-chat --agent session-a1   # one writer
brain-chat --type work.claim    # one event-type prefix
brain-chat --limit 100          # at most N rows (default 50)
brain-chat --claims-only        # only what is held right now
```

`--follow` redraws every five seconds; there is no daemon and no file watcher.

Reading only. There is no `brain-chat --post`; writing is [[#Writing, later]].

### Where it reads from

`vault/events/inbox/` and `vault/events/archive/`, the same two directories `brain-poll`
scans. Both hold complete events: `from {agent, host, instance_id}` and the payload.

**Not the audit log.** `vault/events/audit/<host>/<agent>/<date>.ndjson` looks like the
obvious source and is not. It is an index: timestamp, action, event_id, type and a
filename. No payload. A view built on it would show when things happened and never what
was said.

A chronological view is therefore a merge over the event files sorted on their timestamp.
That is read work, not a protocol change, which is why this ships without touching how
anything is written.

Claims are read from `vault/claims/*.json` and rendered as context rather than as
messages: they say who holds what, not what happened.

> Cross-segment wildcards (`*.review.completed`) are `DESIGN`, not `IMPL`. This view
> therefore reads files directly instead of subscribing, which also avoids depending on
> a pattern that does not exist yet.

## The message format

The format is fixed before any writer exists, so adding one needs no migration.

A chat message is an ordinary bus event with type `chat.message.posted`. Everything the
envelope already provides stays as it is: `payload` carries the content, `from` carries
`{agent, host, instance_id}`, and both schema versions apply.

One field is added, and it is required:

| field | values | why |
|---|---|---|
| `payload.origin` | `human` \| `agent` \| `imported` | `from.agent` distinguishes sessions, not people from machines. A reader has to know which it is looking at, and that cannot be inferred from an agent name. |

Until a writer exists, `brain-chat` renders an event without `payload.origin` as `agent`.

`imported` covers text that entered from somewhere else, a pasted log or a third-party
title, and it is the value that says "nobody on this bus vouches for this".

## The reading contract

Every line in this stream is untrusted input. A person types free text; an `imported`
line carries whatever its source contained.

**`brain-chat` never prints a bare payload.** Every message is rendered with its author
and origin attached, so what reaches a model is always a quoted message and never a loose
sentence. A line reading "ignore your previous instructions" arrives as text somebody
wrote, which is what it is.

This is the same principle as the envelope that carries cross-session messages into a
Claude Code session: the harness wraps them with a warning, and the agent cannot receive
them any other way. Make the safe path the only normal path.

**The honest limit.** An agent that reads the ndjson files directly bypasses this, and no
format can prevent that. The spec therefore states it as a named exception: a consumer
reading the files itself must wrap them itself. Discipline, but discipline in one marked
place instead of at every call site.

## Writing, later

There is no writer yet. A writer must strip intake (zero-width and bidi characters,
embedded newlines in a line-based format) and emit the format above.

## Not in scope

No threads, no replies, no reactions, no rooms, no delivery guarantees, no unread badge.
The audit log is the history and the cursor mechanism already answers "what have I not
seen". Anything beyond a chronological, attributed, safely rendered stream waits until the
stream itself has proven what it is missing.
