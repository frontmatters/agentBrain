---
id: extract-learnings
name: Extract Learnings (behavior)
version: 0.1.0
install: bash system/addons/extract-learnings/install.sh
command: bun
privacy: sends-docs
install_method: self
test: bun test tests/core.test.ts
support:
  pi: full
  claude: full
  copilot: unknown
outputs:
  - local/learnings/extracted/*.md
---

# Extract Learnings (behavior add-on)

Auto-extracts durable learnings from a session before compaction, into
`local/learnings/extracted/`. Pi adapter = `system/pi-config/extensions/extract-learnings.ts`
(`session_before_compact`). Claude adapter = a `PreCompact` hook (installed by `install.sh`).
Privacy `sends-docs`: session text is sent to the configured summary model.
