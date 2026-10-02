---
id: event-bus
name: Event Bus (transport)
version: 0.3.1
author: frontmatters
kind: framework
install: bash system/addons/event-bus/install.sh
command: bash
privacy: local
install_method: self
test: bash tests/test-event-bus.sh
support:
  pi: full
  claude: full
  copilot: full
  codex: full
  gemini: full
  aider: full
  abh: unknown
outputs:
  - vault/events/inbox/*.json
  - vault/events/archive/*.json
  - vault/events/audit/<host>/<agent>/*.ndjson
  - vault/events/cursors/<host>/<agent>/seen-ids.set
---

# Event Bus (transport add-on)

Filesystem-based pub/sub for cross-agent communication. Agents
emit JSON envelopes into `vault/events/inbox/`; consumers poll with a sync-safe
cursor (`seen-ids.set` + lookback window).

- **Use**: `bash system/addons/event-bus/bin/brain-emit --help` (no install
  needed for v1 — scripts run directly from the addon path).
- **Privacy**: emission and polling are filesystem-only. Cross-machine delivery requires
  separately configured vault sync; the bus itself does not perform network I/O.

Dependencies: `bash` (POSIX), `jq`, `python3`, `openssl`. All available on
macOS/Linux defaults; on Windows requires git-bash + bundled jq/python.
