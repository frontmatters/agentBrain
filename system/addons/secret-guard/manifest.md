---
id: secret-guard
name: Secret Guard
version: 0.1.0
author: frontmatters
kind: framework
install: bash system/addons/secret-guard/install.sh
command: python3
default_enabled: false
privacy: local-only
install_method: self
test: python3 tests/test-secret-guard.py
support:
  pi: full
  claude: full
  copilot: none
  codex: none
  abh: unknown
outputs:
  - ~/.claude/settings.json
---

# Secret Guard

Opt-in PreToolUse and Pi tool_call guard. See README.md for coverage and limits.
