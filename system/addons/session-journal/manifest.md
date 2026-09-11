---
id: session-journal
name: Session Journal (behavior)
version: 0.1.1
author: frontmatters
install: bash system/addons/session-journal/install.sh
command: bash
privacy: local-only
install_method: self
test: bash tests/test-journal.sh
support:
  pi: none
  claude: full
  copilot: unknown
  abh: unknown
outputs:
  - vault/sessions/session-journal.md
  - vault/sessions/archive/YYYY-MM/*.md
---

# Session Journal (behavior add-on)

Keeps `vault/sessions/session-journal.md` populated during and after Claude Code sessions, so the existing session-continuity flow (defined in `system/agent-config/shared.md`) actually has content to archive.

Three triggers, all configurable via `vault/sessions/journal-config.json`:

- **Stop hook** — fills the journal at session end (bash-parses transcript)
- **Autosave hook** — PostToolUse with mtime-based throttling during the session
- **`/journal` slash command** — manual show/save/archive

Privacy `local-only`: nothing leaves the machine; transcript is parsed locally with `python3`.
