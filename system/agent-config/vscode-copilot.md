---
date: 2026-05-17
type: system
tags: [agent-config, vscode-copilot]
id: 68a53255-de67-530d-917c-da1b3a0d17cb
---

# VS Code Copilot Agent Config

VS Code Copilot can point at `.github/copilot-instructions.md` via user settings.

## VS Code Copilot-specific rules

- Follow `.github/copilot-instructions.md`, `system/agent-config/copilot.md`, and `system/rules.md`.
- `scripts/setup.sh` detects VS Code settings and prints the setting to add manually.
- Keep VS Code user settings as a pointer to the repo instruction file.
