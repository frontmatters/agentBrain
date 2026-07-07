---
id: event-bus
name: Event Bus (transport)
version: 0.3.0
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
outputs:
  - local/events/inbox/*.json
  - local/events/archive/*.json
  - local/events/audit/<host>/<agent>/*.ndjson
  - local/events/cursors/<host>/<agent>/seen-ids.set
---

# Event Bus (transport add-on)

Filesystem-based pub/sub for cross-agent + cross-machine communication. Agents
emit JSON envelopes into `local/events/inbox/`; consumers poll with a sync-safe
cursor (`seen-ids.set` + lookback window).

- **Use**: `bash system/addons/event-bus/bin/brain-emit --help` (no install
  needed for v1 — scripts run directly from the addon path).
- **Privacy**: `no-network` — events never leave the filesystem. Cross-machine
  transport piggybacks on the existing gitea sync of `local/events/`.

Dependencies: `bash` (POSIX), `jq`, `python3`, `openssl`. All available on
macOS/Linux defaults; on Windows requires git-bash + bundled jq/python.
