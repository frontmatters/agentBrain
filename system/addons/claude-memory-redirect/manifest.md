---
id: claude-memory-redirect
name: Claude Memory Redirect (behavior)
version: 0.1.1
author: frontmatters
install: bash system/addons/claude-memory-redirect/install.sh
command: bash
# On by default in a fresh install; the user can untick it.
default_enabled: true
privacy: local-only
install_method: self
test: bash tests/test-redirect.sh
support:
  pi: none
  claude: full
  copilot: unknown
  abh: unknown
outputs:
  - vault/memories/projects/<project-slug>/*.md
---

# Claude Memory Redirect (behavior add-on)

Routes Claude Code's per-project auto-memory (`~/.claude/projects/<encoded-cwd>/memory/`) into agentBrain so all persistent knowledge lives in one canonical store with agentBrain frontmatter conventions (UUID5, `type`, `tags`).

Three switchable modes, plus a permanent instruction layer (CLAUDE.md):

- **symlink** (default): replace the Claude memory directory with a symlink to `vault/memories/projects/<slug>/`.
- **sync_hook**: leave the original in place, mirror every write to agentBrain via PostToolUse hook, optionally delete originals.
- **instruction_only**: no file ops; relies entirely on the CLAUDE.md instruction to send Claude through agentBrain skills.
- **disabled**: addon does nothing at runtime.

CLAUDE.md update is added by `install.sh` regardless of mode — it is the cheapest layer and serves as both documentation and preventive instruction.

One-shot `claude-memory-migrate.sh` normalises any pre-existing memory files to agentBrain frontmatter before activation.

Privacy `local-only`: nothing leaves the machine.
