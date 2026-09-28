---
id: git-email-guard
name: Git Email Guard (pre-commit hook)
version: 0.1.2
author: frontmatters
install: bash system/addons/git-email-guard/install.sh
command: bash
# On by default in a fresh install; the user can untick it.
default_enabled: true
privacy: local-only
install_method: self
test: bash tests/test-git-email-guard.sh
support:
  pi: full
  claude: full
  copilot: full
  abh: unknown
outputs:
  - .git/hooks/pre-commit (symlink in target repo)
  - .gitemail-allowed (committed whitelist in target repo)
---

# Git Email Guard

Per-repo pre-commit hook that blocks commits when `user.email` is not in the repo's `.gitemail-allowed` whitelist. Prevents personal-email leakage to public mirrors.

See `README.md` for full usage.
