---
date: 2026-05-24
type: system
tags: [skill, peer-review, rca, incident]
id: 1df9ffe9-bcaf-50bb-aac3-bb76160084f2
---

# peer-review v1.4 hang — RCA (2026-05-24)

Two `peer-review` invocations hung silently for 1h+ before they were noticed. Root causes:

1. **No client-side timeout** in `pi`-CLI — the reviewer process never aborted on its own.
2. **Output-masking pipeline** — calling shape `bash ... | tail -N` swallowed the lack of stderr/stdout, so the hang was invisible from the parent shell.

v1.4 closes both gaps via the `--timeout=<seconds>` flag (default 300s) with a watchdog that sends SIGTERM, then SIGKILL after 3 more seconds, and a stderr heartbeat every 30s during the wait. See `../SPEC.md` §"Watchdog timeout" for the full mechanism.
