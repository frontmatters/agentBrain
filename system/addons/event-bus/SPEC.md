---
date: 2026-05-25
type: spec
tags: [spec]
source: session
version: 0.3.0
id: 16a7b04c-1ddf-50ef-9989-4f65a1a803c3
---

# event-bus SPEC — protocol layer

The wire-protocol for events on the agentBrain bus: envelope, topics, threading, routing.
For storage (filesystem, cursor, audit, retention) see [[SPEC-storage]]. For the
built-in handshake see [[SPEC-ping]].

**Status legend used throughout**:
- `IMPL` — implemented + tested in v0.3
- `PARTIAL` — implemented with gaps (gaps documented inline)
- `DESIGN` — designed but not coded; achievable in v0.4+ if needed
- `BACKLOG` — future intent; may be YAGNI

---

## 1. Envelope (IMPL)

Every event on the bus is a JSON object with this shape:

```json
{
  "event_id":                "<uuid5>",
  "type":                    "<context>.<entity>.<action>",
  "envelope_schema_version": 1,
  "payload_schema_version":  1,
  "from":                    { "agent": "...", "host": "...", "instance_id": "..." },
  "to":                      { "agents": [], "hosts": [], "broadcast": false },
  "timestamp":               "<ISO-8601 µs Z>",
  "correlation_id":          "<event_id of thread initiator>",
  "payload":                 { ... },

  "reply_to":                { "agent": "...", "host": "..." },   // optional
  "ref":                     "<vault-relative-path>",             // optional
  "in_reply_to":             "<event_id>",                        // optional
  "causation_ids":           ["<event_id>", ...]                  // optional
}
```

**Required**: `event_id`, `type`, `envelope_schema_version`, `payload_schema_version`,
`from`, `to`, `timestamp`, `correlation_id`, `payload`.

**Optional**: `reply_to`, `ref`, `in_reply_to`, `causation_ids`.

**Reserved domain**: none of the envelope-field names may appear in `payload`.

### Unknown-field policy

- **Top-level envelope**: REJECT (strict) — forward-compat via `envelope_schema_version` bump.
- **Inside `from`/`to`/`reply_to`**: REJECT (routing must be deterministic).
- **Inside `payload`**: per-type schema may allow extras; default reject.

> `IMPL` — `scripts/check-events.sh` runs in doctor and validates every event in
> `local/events/inbox/` + `local/events/archive/` against this schema (required
> fields, type-regex, UUID format, ISO-8601 timestamp, sub-object structure).

---

## 2. Topics (IMPL)

Topic-naming for the `type` field:

**Format**: `<context>.<entity>.<action>` — 3-segment, dot-separated, lowercase, kebab-case within segment.

- **Context** — the skill or subsystem that owns the event (`peer-review`, `notes`, `tasks`, `alerts`, `system`)
- **Entity** — what the event is about (`review`, `learning`, `task`, `config`, `bus`)
- **Action** — what happened (past-tense for events; imperative for commands)

```
peer-review.review.requested
peer-review.review.completed
notes.learning.candidate
system.bus.ping
```

### Verb convention

- **Past-tense = event** (state HAS changed): `requested`, `completed`, `failed`, `cancelled`, `responded`
- **Imperative = command** (instruction TO do something): `cancel`, `retry`, `dispatch`

Rule of thumb: if the bus-handler cannot refuse, it's an event. If it can reject or fail, it's a command.

> `DESIGN` — v0.3 supports events only. Imperative commands need accept/reject/fail/complete lifecycle (deferred).

### Registered types (v0.3)

| Type | Used by | Status |
|---|---|---|
| `peer-review.review.requested` | peer-review skill | IMPL |
| `peer-review.review.completed` | peer-review skill | IMPL |
| `system.bus.ping` | brain-ping | IMPL |
| `system.bus.pong` | ping-listener template | IMPL |
| `peer-review.review.question` | multi-turn dialog | DESIGN (no code path) |
| `peer-review.review.response` | multi-turn dialog | DESIGN (no code path) |
| `notes.learning.candidate` | learnings auto-extract | BACKLOG |
| `tasks.task.assigned` / `.completed` | multi-agent delegation | BACKLOG |
| `alerts.health.degraded` | health monitoring | BACKLOG |

### Subscription patterns

Consumers can filter:
- Specific: `peer-review.review.completed`
- Glob within segment: `peer-review.review.*` (IMPL via `brain-poll --type=`)
- Wildcards across segments: `*.review.completed` — DESIGN, not in `brain-poll` yet

### Per-topic payload schemas

> `BACKLOG` — `system/event-schemas/<type>.schema.md` directory not built. Payload
> shape is currently informal (whatever the producer emits). Add when a third
> consumer needs to validate without reading producer code.

---

## 3. Threading (IMPL)

How events link into conversations.

### event_id derivation (non-circular)

```
nonce    = openssl rand -hex 4   (8 hex chars)
event_id = uuid5(BRAIN_NS, type ":" iso_µs_timestamp ":" from.agent ":" from.host ":" from.instance_id ":" nonce)
```

`BRAIN_NS` = namespace UUID from `brain.json`. `event_id` is derived **before** the
filename; filename gets `<id8>` as informational prefix only. No circularity.

### Threading fields

| Field | When | Example |
|---|---|---|
| `event_id` | always — per-event unique | `a4b3c2d1-...` |
| `in_reply_to` | direct response to one event | `<event_id>` |
| `correlation_id` | multi-turn thread marker; initiator: `correlation_id == event_id` | `<event_id>` |
| `causation_ids` (optional list) | events that caused this; supports fan-in | `[<id>, <id>, ...]` |

### Patterns

**1-on-1 reply** (IMPL — used by peer-review):
```
A: peer-review.review.requested   (event_id=X, correlation_id=X)
B: peer-review.review.completed   (event_id=Y, correlation_id=X, in_reply_to=X)
```

**Multi-turn dialog** (DESIGN):
```
A: peer-review.review.requested   (event_id=A, correlation_id=A)
B: peer-review.review.question    (correlation_id=A, in_reply_to=A)
C: peer-review.review.response    (correlation_id=A, in_reply_to=B)
D: peer-review.review.completed   (correlation_id=A, in_reply_to=A, causation_ids=[C])
```

**Fan-in / aggregate** (IMPL — used for multi-tier peer-review):
```
A: requested  (correlation_id=A)
B: completed  (correlation_id=A, in_reply_to=A, reviewer=tier-20b)
C: completed  (correlation_id=A, in_reply_to=A, reviewer=tier-120b)
D: completed  (correlation_id=A, in_reply_to=A, reviewer=codex)
```
Multiple reviewers respond to same request; all share correlation_id.

### Reconstruct a thread

```bash
find $AGENTBRAIN_DIR/local/events/inbox -name "*.json" \
  | xargs grep -l '"correlation_id": "<id>"' \
  | sort
```

Higher-level: `bash bin/peer-review --list --correlation=<id>` if using peer-review skill.

---

## 4. Routing (IMPL)

How `from`/`to`/`reply_to` direct events.

### Envelope routing fields

```json
{
  "from":     { "agent": "pi",       "host": "host-a", "instance_id": "pid-12345" },
  "to":       { "agents": ["claude"], "hosts": ["host-a"], "broadcast": false },
  "reply_to": { "agent": "claude",   "host": "host-a" }
}
```

| Field | Required | Meaning |
|---|---|---|
| `from.agent` / `.host` / `.instance_id` | yes | Who published |
| `to.agents` | yes (can be `[]` if broadcast) | Target agents |
| `to.hosts` | no (default = all hosts) | Host filter |
| `to.broadcast` | yes | `true` → ignore agents/hosts; reach everyone matching |
| `reply_to` | no | Where replies go (default = `from`) |

### Routing matrix

| Scenario | `to.agents` | `to.hosts` | `to.broadcast` |
|---|---|---|---|
| Specific agent, any host | `["claude"]` | `[]` | false |
| Specific agent on specific host | `["claude"]` | `["host-a"]` | false |
| All instances of an agent across hosts | `["claude"]` | `[]` | false |
| All agents on one host | `[]` | `["host-a"]` | true (host-scoped broadcast) |
| Everyone | `[]` | `[]` | true |

### Consumer-side filter (`matches_me` in brain-poll)

```
matches_me(event, self):
  if event.to.broadcast == true:
    return event.to.hosts is empty OR self.host in event.to.hosts
  else:
    return self.agent in event.to.agents AND
           (event.to.hosts is empty OR self.host in event.to.hosts)
```

Cursor yields ONLY events where `matches_me` is true. Non-matching events are skipped.

### Multi-machine considerations

- Hostnames: `hostname -s` (short, no dots) consistently
- Empty `to.hosts: []` = "any host", NOT "current host"
- `instance_id` should be a UUID per agent-launch (PID is recyclable; v0.3 brain-emit uses `uuidgen` fallback when env-var not set)

### Trust model

> `IMPL`: v0.3 uses synced-repo trust — anyone with gitea push-access can publish.
> No crypto signatures.
>
> `BACKLOG (v2)`: optional `from.signature` field + per-agent pubkey in `system/agent-keys/`.

---

## 5. Implementation snapshot (v0.3)

| Concern | File | Status |
|---|---|---|
| Envelope build + atomic-write | `bin/brain-emit` | IMPL |
| Topic regex validation | `bin/brain-emit` (`^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$`) | IMPL |
| Threading (event_id, correlation, in_reply_to) | `bin/brain-emit` | IMPL |
| Causation_ids list | `bin/brain-emit --causation-ids=` | IMPL (consumers not using yet) |
| Routing matches_me | `bin/brain-poll` | IMPL |
| Subscription glob filter | `bin/brain-poll --type=` | PARTIAL (segment-glob only, no cross-segment wildcards) |
| Per-type payload schemas | — | BACKLOG |
| Envelope strict validator | `scripts/check-events.sh` (doctor) | IMPL |

---

## 6. Design history

- v1-v4 (monolithic): `local/backlog/2026-05-24-internal-event-bus-design.md` — 30KB doc with internal drift across 4 Pi review rounds
- v5 (decomposition): 9 separate topic-specs in `local/skills/event-bus/`
- v6 (migration): topic-specs moved to `system/addons/event-bus/`
- **v0.3 (this consolidation)**: 9 specs → 3 (protocol, storage, ping); IMPL/PARTIAL/DESIGN/BACKLOG markers added; aspirational-only specs trimmed

## Related

- [[README]] — quickstart + script usage
- [[SPEC-storage]] — filesystem + cursor + audit + retention
- [[SPEC-ping]] — built-in smoketest protocol
- `system/skills/peer-review/` — first real consumer (v2.x)
