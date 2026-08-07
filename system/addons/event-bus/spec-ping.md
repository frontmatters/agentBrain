---
date: 2026-05-25
type: spec
tags: [spec]
source: session
version: 0.3.0
id: 22ab17cd-bcd7-513a-8743-315a524d9e09
---

# event-bus SPEC-ping — built-in smoketest

`system.bus.ping` / `system.bus.pong` handshake to validate that two agents
can reach each other AND understand each other before trusting business-logic
events. Useful for installation verification, pre-flight checks, debugging,
and health monitoring.

For envelope/routing/threading see [[SPEC]]. For filesystem/cursor see [[SPEC-storage]].

**Status**: fully `IMPL` in v0.3 (brain-ping script + ping-listener template).

---

## Protocol

### Ping

```json
{
  "type":                    "system.bus.ping",
  "envelope_schema_version": 1,
  "payload_schema_version":  1,
  "from":                    { "agent": "claude", "host": "host-a", "instance_id": "..." },
  "to":                      { "agents": ["pi"], "hosts": [], "broadcast": false },
  "timestamp":               "<ISO-8601 µs Z>",
  "correlation_id":          "<event_id of this ping>",
  "payload": {
    "sent_at": "<envelope.timestamp>",
    "echo":    "<random-token, openssl rand -hex 16>"
  }
}
```

### Pong

```json
{
  "type":           "system.bus.pong",
  "from":           { "agent": "pi", "host": "host-a", "instance_id": "..." },
  "to":             { "agents": ["claude"], "hosts": [], "broadcast": false },
  "in_reply_to":    "<ping event_id>",
  "correlation_id": "<from ping>",
  "timestamp":      "<ISO-8601 µs Z>",
  "payload": {
    "sent_at":      "<from ping payload>",
    "received_at":  "<when listener received the ping>",
    "responded_at": "<when this pong was emitted>",
    "echo":         "<MUST equal ping.echo for payload-integrity>",
    "pong_by":      { "agent": "pi", "host": "host-a", "instance_id": "..." }
  }
}
```

---

## `brain-ping` script (IMPL)

```bash
brain-ping --agent=<target> [--timeout=<sec>] [--hosts=<h1,h2>] [--interval=<ms>] [--from=<agent>] [--quiet]
```

Behavior:
- Generates random echo-token via `openssl rand -hex 16`
- Emits `system.bus.ping` with `to.agents=[target]`
- Polls for matching pong (in_reply_to=ping) until `--timeout` (default 10s)
- Verifies `echo` token matches → payload-integrity proof
- Prints round-trip latency + pong_by identity

Exit codes:
- `0` — success: pong received with matching echo
- `1` — timeout: no pong before deadline
- `2` — echo mismatch (payload integrity failure)
- `3` — schema-invalid pong (missing required field)

---

## What ping/pong validates

| Aspect | Tested? | How |
|---|---|---|
| Agent listener running | ✓ | No pong = not reachable |
| Agent can emit | ✓ | Pong IS an emit; works ⇒ emit works |
| Filesystem layout | ✓ | Both files land correctly |
| Schema validation | ✓ | Pong must be valid envelope + payload |
| Cursor / dedup logic | ✓ | Pong must use event_id correctly |
| Round-trip latency | ✓ | `responded_at − sent_at` |
| Payload integrity | ✓ | Echo-token must exactly match |
| Cross-version compat | ✓ | Mismatch on `envelope_schema_version` would fail |
| Multi-machine sync | ⚠ | Cross-host ping proves sync works — only when events/ are git-synced (DESIGN, see [[SPEC-storage]]) |
| Business-logic correctness | ✗ | Out of scope — transport only |

---

## Responder contract (ping-listener.template.sh)

Every agent that registers as a bus participant SHOULD have a ping-listener.
Template lives at `system/addons/event-bus/templates/ping-listener.template.sh`.

Listener responsibilities:
1. Subscribe to `system.bus.ping` filtered by `to.agents` includes self
2. On match: build pong with `received_at` + `responded_at`, copy echo, set `in_reply_to`
3. Emit pong within N seconds (default 5s)
4. Idempotent: never pong the same ping twice (seen-ids dedup)

---

## When to use

| Scenario | Command |
|---|---|
| Installation: prove bus-readiness | `brain-ping --agent=<each-installed-agent>` |
| Pre-flight in another skill | `brain-ping --agent=pi && peer-review ...` |
| Debugging "is agent X still up?" | `brain-ping --agent=X --timeout=5` |
| Health monitoring | Periodic ping → metrics file (BACKLOG: `local/metrics/bus-health.tsv`) |
| CI / doctor | `check-bus-handshake.sh` validator (BACKLOG) |

---

## Related

- [[SPEC]] — envelope + routing + threading
- [[SPEC-storage]] — filesystem layout
- `bin/brain-ping` — the script
- `templates/ping-listener.template.sh` — responder template
