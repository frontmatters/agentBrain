---
date: 2026-05-18
type: system
tags: [security, privacy, guidance]
id: 25e7b08c-2856-5cdc-b83d-7c2d983290fb
---

# Security Guidance

## Core rule

Never commit secrets, credentials, personal infrastructure details, or private identifiers to the public layer.

Store those in `local/security/` (gitignored) or your secrets helper / keychain.

## What must stay private

| Category                 | Examples                            | Where instead             |
| ------------------------ | ----------------------------------- | ------------------------- |
| API tokens, PATs         | `gh_...`, `sk-...`, `AKIA...`       | keychain / secrets helper |
| Hostnames, IPs           | `mymachine.local`, `192.168.x.x`    | `local/security/`         |
| Machine-specific notes   | keychain setup, auth migration      | `local/setup-history/`    |
| Private URLs             | internal Gitea, private repos       | `local/integrations/`     |
| Credential rotation logs | "rotated X on date Y"               | `local/security/`         |
| Private infrastructure   | Docker hosts, DB connection strings | `local/integrations/`     |

## Privacy scan

Run before every public commit:

```bash
scripts/privacy-scan.sh            # scan all tracked files
scripts/privacy-scan.sh --staged   # scan staged files only
```

The pre-commit hook runs the staged scan automatically once `git config core.hooksPath .githooks` is active (set by `setup.sh` and `bootstrap-pi-macos.sh`).

CI also runs the scan on every push via `.github/workflows/privacy-scan.yml`.

## Local denylist

Add personal identifiers (username, machine name, org domains) to:

```
local/security/privacy-denylist.txt
```

One `grep -E` pattern per line. This file is gitignored and never pushed.

## If a secret was committed accidentally

1. **Rotate / revoke immediately** — treat it as compromised.
2. Rewrite history: `git filter-repo --path <file> --invert-paths` or BFG Repo Cleaner.
3. Force-push to all remotes.
4. Notify affected services if necessary.

Do not just delete the file in a new commit — the secret remains in git history.

## Secrets helper

Credentials are stored in the macOS keychain and accessed via `~/bin/gitea-helper.sh` (or equivalent secrets helper). See `local/integrations/` for integration-specific notes.

Never print token values in terminal output that Pi might capture in its session log.
